<?php
/**
 * Plugin Name: DL Site Cloner
 * Plugin URI:  https://www.carevents.com/
 * Description: Copies ACF field groups, ACF post types and taxonomies, terms, content, options and plugin state from one site in the network to another. Built for standing up a new regional blog (EU, AU) against the UK one.
 * Version:     1.0.0
 * Author:      DriveLife
 * Network:     true
 * Requires at least: 6.0
 * Requires PHP: 7.4
 *
 * HOW IT WORKS
 *
 * One job at a time, stored as a network option, stepped through by AJAX so
 * that a few thousand posts do not have to fit inside one PHP request. Each
 * step reads from the source blog into plain arrays, restores the blog, then
 * writes to the target: nothing holds a WP object across a switch_to_blog,
 * because object caches and ACF's own stores are keyed per blog and an object
 * read on one blog will happily lie to you on another.
 *
 * Everything is matched on a stable name rather than an ID -- field groups by
 * their ACF key, posts by post_name, terms by slug -- so running it twice
 * updates what is there instead of making a second copy. That is what makes
 * it safe to re-run after fixing one thing.
 *
 * WHAT IT DOES NOT DO
 *
 * It does not rewrite IDs buried inside post meta, except where it says so.
 * A post id is only unique within a blog, so an ACF relationship field
 * pointing at post 412 on the UK site points at a different post, or at
 * nothing, on the new one. Attachment ids are remapped when you ask for it,
 * because that map is built here and can be trusted. Everything else is
 * reported in the log for you to look at.
 */

if (!defined('ABSPATH')) {
    exit;
}

if (!is_multisite()) {
    return;
}

final class DL_Site_Cloner
{
    const VERSION = '1.0.0';

    /** Super admins only. Cloning a site is not a per-site capability. */
    const CAP = 'manage_network_options';

    const SLUG = 'dl-site-cloner';
    const NONCE = 'dl_sc_nonce';

    /** The one job in flight, as a network option. */
    const JOB = 'dl_sc_job';

    /** Posts or terms per AJAX request. Low enough for slow shared hosting. */
    const BATCH = 25;

    /**
     * Options that are never copied, whatever is typed into the box.
     *
     * Each of these either identifies the site (a copied siteurl takes the
     * target offline) or is derived state that WordPress rebuilds for itself.
     * active_plugins, template and stylesheet are excluded here because they
     * have their own step, which activates properly rather than writing the
     * option behind WordPress's back.
     */
    const OPTION_DENY = [
        'siteurl',
        'home',
        'blogname',
        'admin_email',
        'new_admin_email',
        'upload_path',
        'upload_url_path',
        'cron',
        'rewrite_rules',
        'active_plugins',
        'template',
        'stylesheet',
        'current_theme',
        'db_version',
        'initial_db_version',
        'recently_edited',
        'recently_activated',
        '_transient_',
        '_site_transient_',
        'wp_user_roles',
    ];

    /** Meta keys that describe an edit session rather than the content. */
    const META_SKIP = ['_edit_lock', '_edit_last'];

    public static function boot(): void
    {
        $self = new self();

        add_action('network_admin_menu', [$self, 'menu']);
        add_action('wp_ajax_dl_sc_compare', [$self, 'ajax_compare']);
        add_action('wp_ajax_dl_sc_plan', [$self, 'ajax_plan']);
        add_action('wp_ajax_dl_sc_step', [$self, 'ajax_step']);
    }

    // ───────────────────────────────────────────────────────── admin page ──

    public function menu(): void
    {
        add_submenu_page(
            'settings.php',
            'Site Cloner',
            'Site Cloner',
            self::CAP,
            self::SLUG,
            [$this, 'render']
        );
    }

    public function render(): void
    {
        if (!current_user_can(self::CAP)) {
            wp_die('You need to be a network administrator to use this.');
        }

        $sites = get_sites(['number' => 200, 'orderby' => 'id']);
        $current = get_current_blog_id();

        // Post types and taxonomies as the CURRENT blog knows them. The
        // source blog may register more, but a network admin screen runs on
        // the network's main site, and in this network every blog runs the
        // same theme -- so this list is the right one in practice. The job
        // asks the source blog again before it copies anything.
        $post_types = get_post_types(['public' => true], 'objects')
            + get_post_types(['public' => false, 'show_ui' => true], 'objects');

        // Attachments ride along with the posts that use them, through the
        // featured-image option, rather than being copied as a type.
        unset($post_types['attachment']);

        // nav_menu_item is registered with show_ui false, so neither call
        // above returns it -- and menus are one of the things most worth
        // copying to a new blog.
        $menu_item = get_post_type_object('nav_menu_item');
        if ($menu_item) {
            $post_types['nav_menu_item'] = $menu_item;
        }

        ksort($post_types);

        $taxes = get_taxonomies([], 'objects');
        ksort($taxes);

        $acf = function_exists('acf_get_field_groups');

        ?>
        <div class="wrap">
            <h1>Site Cloner</h1>

            <p class="description" style="max-width:46em">
                Copies structure and content from one site in this network to
                another. Matches on names rather than IDs, so running it again
                updates what is already there instead of duplicating it.
                <strong>Start with Dry run</strong> — it reports exactly what it
                would do and writes nothing.
            </p>

            <?php if (!$acf) : ?>
                <div class="notice notice-warning inline">
                    <p>
                        ACF is not loaded on this screen, so the field group and
                        post type steps are unavailable. Network-activate ACF,
                        or run this from a site where it is active.
                    </p>
                </div>
            <?php endif; ?>

            <form id="dl-sc-form" onsubmit="return false">
                <table class="form-table" role="presentation">
                    <tr>
                        <th scope="row"><label for="dl-sc-source">Copy from</label></th>
                        <td>
                            <select id="dl-sc-source" name="source">
                                <?php foreach ($sites as $s) : ?>
                                    <option value="<?php echo (int) $s->blog_id; ?>"
                                        <?php selected((int) $s->blog_id, $current); ?>>
                                        <?php echo esc_html(
                                            $s->blog_id . ' — ' . $s->domain . $s->path
                                        ); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="dl-sc-target">Copy to</label></th>
                        <td>
                            <select id="dl-sc-target" name="target">
                                <?php foreach ($sites as $s) : ?>
                                    <option value="<?php echo (int) $s->blog_id; ?>">
                                        <?php echo esc_html(
                                            $s->blog_id . ' — ' . $s->domain . $s->path
                                        ); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <p class="description">
                                Existing content on the target with a matching
                                slug is <strong>overwritten</strong>.
                            </p>
                        </td>
                    </tr>

                    <tr>
                        <th scope="row">Structure</th>
                        <td>
                            <fieldset>
                                <label>
                                    <input type="checkbox" name="acf_groups" checked
                                        <?php disabled(!$acf); ?>>
                                    ACF field groups
                                </label><br>
                                <label>
                                    <input type="checkbox" name="acf_post_types" checked
                                        <?php disabled(!$acf); ?>>
                                    ACF post types and taxonomies
                                    <span class="description">
                                        (only the ones registered through ACF's UI —
                                        anything your theme registers in code is already
                                        on every blog)
                                    </span>
                                </label><br>
                                <label>
                                    <input type="checkbox" name="plugins">
                                    Active plugins and theme
                                </label>
                            </fieldset>
                        </td>
                    </tr>

                    <tr>
                        <th scope="row">Taxonomy terms</th>
                        <td>
                            <select name="taxonomies" id="dl-sc-taxes" multiple size="8"
                                style="min-width:22em">
                                <?php foreach ($taxes as $name => $tax) : ?>
                                    <option value="<?php echo esc_attr($name); ?>"
                                        <?php selected(in_array($name, ['club_category', 'nav_menu'], true)); ?>>
                                        <?php echo esc_html($tax->label . ' — ' . $name); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <p class="description">
                                Copied before the posts, so that posts can be filed
                                under them. Term meta (ACF fields on terms) comes too.
                            </p>
                        </td>
                    </tr>

                    <tr>
                        <th scope="row">Content</th>
                        <td>
                            <select name="post_types" id="dl-sc-types" multiple size="10"
                                style="min-width:22em">
                                <?php foreach ($post_types as $name => $pt) : ?>
                                    <option value="<?php echo esc_attr($name); ?>"
                                        <?php selected(in_array($name, ['page', 'nav_menu_item'], true)); ?>>
                                        <?php echo esc_html($pt->label . ' — ' . $name); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>

                            <p style="margin-top:.8em">
                                <label>
                                    <input type="checkbox" name="drafts" checked>
                                    Include drafts and private posts
                                </label><br>
                                <label>
                                    <input type="checkbox" name="attachments">
                                    Copy featured images, files and all
                                    <span class="description">
                                        (duplicates the file into the target's own
                                        uploads folder and repoints the thumbnail)
                                    </span>
                                </label><br>
                                <label>
                                    <input type="checkbox" name="remap_attachment_meta">
                                    Also repoint attachment IDs found in post meta
                                    <span class="description">
                                        (ACF image and gallery fields. Only touches a
                                        value that is exactly the ID of an attachment
                                        copied in this run.)
                                    </span>
                                </label>
                            </p>
                        </td>
                    </tr>

                    <tr>
                        <th scope="row"><label for="dl-sc-options">Options</label></th>
                        <td>
                            <textarea id="dl-sc-options" name="options" rows="5"
                                class="large-text code"
                                placeholder="One per line. A trailing * matches a prefix."
>options_*
_options_*
theme_mods_*
blogdescription
date_format
time_format
start_of_week</textarea>
                            <p class="description">
                                ACF options-page values live in
                                <code>options_&lt;field&gt;</code>, which is what the
                                first two lines are for. Anything that identifies the
                                site — <code>siteurl</code>, <code>home</code>,
                                <code>active_plugins</code> — is refused whatever you
                                put here.
                            </p>
                        </td>
                    </tr>

                    <tr>
                        <th scope="row">Dry run</th>
                        <td>
                            <label>
                                <input type="checkbox" name="dry_run" id="dl-sc-dry" checked>
                                Report what would happen and write nothing
                            </label>
                        </td>
                    </tr>
                </table>

                <p class="submit">
                    <button class="button" id="dl-sc-compare">Compare the two sites</button>
                    <button class="button button-primary" id="dl-sc-go">Run</button>
                    <span class="spinner" id="dl-sc-spin" style="float:none;visibility:hidden"></span>
                </p>
            </form>

            <div id="dl-sc-progress" style="display:none">
                <h2>Progress</h2>
                <p><strong id="dl-sc-stage"></strong> <span id="dl-sc-counts"></span></p>
                <pre id="dl-sc-log" style="max-height:28em;overflow:auto;background:#1d2327;
                    color:#c3c4c7;padding:1em;border-radius:4px;white-space:pre-wrap"></pre>
            </div>
        </div>

        <script>
        (function () {
            const form = document.getElementById('dl-sc-form');
            const go = document.getElementById('dl-sc-go');
            const spin = document.getElementById('dl-sc-spin');
            const wrap = document.getElementById('dl-sc-progress');
            const logEl = document.getElementById('dl-sc-log');
            const stageEl = document.getElementById('dl-sc-stage');
            const countsEl = document.getElementById('dl-sc-counts');
            const nonce = <?php echo wp_json_encode(wp_create_nonce(self::NONCE)); ?>;
            const ajax = <?php echo wp_json_encode(admin_url('admin-ajax.php')); ?>;

            function say(lines) {
                (lines || []).forEach(function (l) {
                    logEl.textContent += l + '\n';
                });
                logEl.scrollTop = logEl.scrollHeight;
            }

            function body(action, extra) {
                const fd = new FormData(form);
                fd.append('action', action);
                fd.append('_wpnonce', nonce);
                // Multi-selects: FormData already repeats the key, but PHP
                // needs the [] suffix to read them as an array.
                const out = new FormData();
                out.append('action', action);
                out.append('_wpnonce', nonce);
                for (const [k, v] of fd.entries()) {
                    if (k === 'action' || k === '_wpnonce') continue;
                    out.append(
                        (k === 'taxonomies' || k === 'post_types') ? k + '[]' : k,
                        v
                    );
                }
                for (const k in (extra || {})) out.append(k, extra[k]);
                return out;
            }

            async function post(action, extra) {
                const res = await fetch(ajax, {
                    method: 'POST',
                    credentials: 'same-origin',
                    body: body(action, extra)
                });
                const json = await res.json();
                if (!json.success) throw new Error(
                    (json.data && json.data.message) || 'Request failed'
                );
                return json.data;
            }

            async function run() {
                go.disabled = true;
                spin.style.visibility = 'visible';
                wrap.style.display = '';
                logEl.textContent = '';

                try {
                    const plan = await post('dl_sc_plan');
                    say(plan.log);

                    let guard = 0;
                    for (;;) {
                        if (++guard > 5000) throw new Error('Too many steps; stopping.');
                        const step = await post('dl_sc_step');
                        say(step.log);
                        stageEl.textContent = step.stage;
                        countsEl.textContent = step.counts || '';
                        if (step.done) break;
                    }
                    say(['', '— finished —']);
                } catch (e) {
                    say(['', 'STOPPED: ' + e.message]);
                } finally {
                    go.disabled = false;
                    spin.style.visibility = 'hidden';
                }
            }

            document.getElementById('dl-sc-compare')
                .addEventListener('click', async function () {
                    wrap.style.display = '';
                    logEl.textContent = '';
                    stageEl.textContent = 'Comparing';
                    countsEl.textContent = '';
                    spin.style.visibility = 'visible';
                    try {
                        const data = await post('dl_sc_compare');
                        say(data.log);
                        stageEl.textContent = 'Comparison';
                    } catch (e) {
                        say(['STOPPED: ' + e.message]);
                    } finally {
                        spin.style.visibility = 'hidden';
                    }
                });

            go.addEventListener('click', function () {
                const src = document.getElementById('dl-sc-source').value;
                const dst = document.getElementById('dl-sc-target').value;
                if (src === dst) {
                    window.alert('Source and target are the same site.');
                    return;
                }
                if (!document.getElementById('dl-sc-dry').checked) {
                    const ok = window.confirm(
                        'This writes to site ' + dst + '. Matching content there ' +
                        'will be overwritten. Continue?'
                    );
                    if (!ok) return;
                }
                run();
            });
        })();
        </script>
        <?php
    }

    // ────────────────────────────────────────────────────────────── ajax ──

    /**
     * Reports what each side has, without touching anything.
     *
     * The question behind "the new blog is missing everything" is usually
     * one of two, and they look the same in the admin: either the post type
     * is not registered on that blog -- because the theme or the plugin that
     * registers it is not active there -- or it is registered and empty.
     * The first is not fixed by copying content, so it is worth knowing
     * which one you have before running anything.
     */
    public function ajax_compare(): void
    {
        $this->guard();

        $source = isset($_POST['source']) ? (int) $_POST['source'] : 0;
        $target = isset($_POST['target']) ? (int) $_POST['target'] : 0;

        if (!$source || !$target || !get_site($source) || !get_site($target)) {
            wp_send_json_error(['message' => 'Pick two sites that exist.']);
        }

        $a = $this->survey($source);
        $b = $this->survey($target);

        $log = [
            sprintf('%-28s %-22s %s', '', 'site ' . $source, 'site ' . $target),
            str_repeat('-', 74),
            sprintf('%-28s %-22s %s', 'theme', $a['theme'], $b['theme']),
            sprintf('%-28s %-22s %s', 'active plugins', $a['plugins'], $b['plugins']),
            sprintf('%-28s %-22s %s', 'ACF field groups', $a['acf_groups'], $b['acf_groups']),
            sprintf('%-28s %-22s %s', 'ACF-registered post types', $a['acf_types'], $b['acf_types']),
            sprintf('%-28s %-22s %s', 'ACF-registered taxonomies', $a['acf_taxes'], $b['acf_taxes']),
            '',
            'POST TYPES  (registered? / how many posts)',
        ];

        foreach (array_unique(array_merge(array_keys($a['types']), array_keys($b['types']))) as $type) {
            $log[] = sprintf('%-28s %-22s %s',
                $type,
                $a['types'][$type] ?? 'not registered',
                $b['types'][$type] ?? 'not registered');
        }

        $log[] = '';
        $log[] = 'TAXONOMIES  (registered? / how many terms)';

        foreach (array_unique(array_merge(array_keys($a['taxes']), array_keys($b['taxes']))) as $tax) {
            $log[] = sprintf('%-28s %-22s %s',
                $tax,
                $a['taxes'][$tax] ?? 'not registered',
                $b['taxes'][$tax] ?? 'not registered');
        }

        $only_a = array_diff(array_keys($a['types']), array_keys($b['types']));
        if ($only_a) {
            $log[] = '';
            $log[] = 'Registered on ' . $source . ' but not on ' . $target . ': '
                . implode(', ', $only_a);
            $log[] = 'Those are registered in code, not stored as content, so '
                . 'copying posts will not bring them. Activate the theme or '
                . 'plugin that registers them on site ' . $target . ' first — '
                . 'the "Active plugins and theme" option does that.';
        }

        wp_send_json_success(['log' => $log]);
    }

    /** What one blog has, for ajax_compare. */
    private function survey(int $blog_id): array
    {
        switch_to_blog($blog_id);
        $this->reset_acf_cache();

        $theme = wp_get_theme();

        $out = [
            'theme' => $theme->get_stylesheet(),
            'plugins' => (string) count((array) get_option('active_plugins', [])),
            'acf_groups' => function_exists('acf_get_field_groups')
                ? (string) count(acf_get_field_groups())
                : 'ACF not loaded',
            'acf_types' => 'n/a',
            'acf_taxes' => 'n/a',
            'types' => [],
            'taxes' => [],
        ];

        if (function_exists('acf_get_internal_post_type_posts')) {
            $out['acf_types'] = (string) count(acf_get_internal_post_type_posts('acf-post-type'));
            $out['acf_taxes'] = (string) count(acf_get_internal_post_type_posts('acf-taxonomy'));
        }

        foreach (get_post_types([], 'names') as $type) {
            if (in_array($type, ['revision', 'oembed_cache', 'user_request',
                'custom_css', 'customize_changeset', 'wp_block',
                'wp_template', 'wp_template_part', 'wp_global_styles',
                'wp_navigation', 'acf-field', 'acf-field-group'], true)) {
                continue;
            }
            $counts = (array) wp_count_posts($type);
            $total = 0;
            foreach (['publish', 'draft', 'pending', 'private', 'future'] as $status) {
                $total += (int) ($counts[$status] ?? 0);
            }
            $out['types'][$type] = sprintf('yes / %d', $total);
        }

        foreach (get_taxonomies([], 'names') as $tax) {
            $count = wp_count_terms(['taxonomy' => $tax, 'hide_empty' => false]);
            $out['taxes'][$tax] = sprintf('yes / %s',
                is_wp_error($count) ? '?' : (int) $count);
        }

        restore_current_blog();

        ksort($out['types']);
        ksort($out['taxes']);

        return $out;
    }

    /** Validates the form, builds the job, and reports the plan. */
    public function ajax_plan(): void
    {
        $this->guard();

        $source = isset($_POST['source']) ? (int) $_POST['source'] : 0;
        $target = isset($_POST['target']) ? (int) $_POST['target'] : 0;

        if (!$source || !$target) {
            wp_send_json_error(['message' => 'Pick a source and a target.']);
        }
        if ($source === $target) {
            wp_send_json_error(['message' => 'Source and target are the same site.']);
        }
        if (!get_site($source) || !get_site($target)) {
            wp_send_json_error(['message' => 'One of those sites does not exist.']);
        }

        $taxonomies = $this->post_list('taxonomies');
        $post_types = $this->post_list('post_types');

        // nav_menu_item without nav_menu is a menu with no menu to live in.
        if (in_array('nav_menu_item', $post_types, true)
            && !in_array('nav_menu', $taxonomies, true)) {
            $taxonomies[] = 'nav_menu';
        }

        $job = [
            'source' => $source,
            'target' => $target,
            'dry_run' => $this->post_bool('dry_run'),
            'drafts' => $this->post_bool('drafts'),
            'attachments' => $this->post_bool('attachments'),
            'remap_attachment_meta' => $this->post_bool('remap_attachment_meta'),
            'acf_groups' => $this->post_bool('acf_groups'),
            'acf_post_types' => $this->post_bool('acf_post_types'),
            'plugins' => $this->post_bool('plugins'),
            'taxonomies' => $taxonomies,
            'post_types' => $post_types,
            'options' => $this->option_patterns(),

            // Where we are, and what we have learned so far.
            'stage' => 'acf',
            'queue' => [],
            'cursor' => 0,
            'map_posts' => [],
            'map_terms' => [],
            'map_attachments' => [],
            'parents' => [],
            'warnings' => 0,
        ];

        update_site_option(self::JOB, $job);

        $src = get_site($source);
        $dst = get_site($target);

        $log = [
            sprintf('%s: site %d (%s) → site %d (%s)',
                $job['dry_run'] ? 'DRY RUN' : 'COPYING',
                $source, $src->domain . $src->path,
                $target, $dst->domain . $dst->path),
            '',
        ];

        if ($job['acf_groups'] || $job['acf_post_types']) {
            $log[] = 'ACF: ' . implode(', ', array_filter([
                $job['acf_groups'] ? 'field groups' : '',
                $job['acf_post_types'] ? 'post types + taxonomies' : '',
            ]));
        }
        if ($taxonomies) {
            $log[] = 'Terms: ' . implode(', ', $taxonomies);
        }
        if ($post_types) {
            $log[] = 'Content: ' . implode(', ', $post_types)
                . ($job['drafts'] ? ' (incl. drafts)' : ' (published only)')
                . ($job['attachments'] ? ' + attachments' : '');
        }
        if ($job['options']) {
            $log[] = 'Options: ' . implode(', ', $job['options']);
        }
        if ($job['plugins']) {
            $log[] = 'Plugins and theme: yes';
        }
        $log[] = '';

        wp_send_json_success(['log' => $log]);
    }

    /** Runs one step of the job in flight. */
    public function ajax_step(): void
    {
        $this->guard();

        $job = get_site_option(self::JOB);
        if (!is_array($job) || empty($job['stage'])) {
            wp_send_json_error(['message' => 'No job in progress. Press Run again.']);
        }

        try {
            [$job, $log, $counts] = $this->step($job);
        } catch (Throwable $e) {
            // Whatever the failure, do not leave a half-finished job behind
            // for the next press of Run to pick up and continue blindly.
            delete_site_option(self::JOB);
            wp_send_json_error([
                'message' => $e->getMessage() . ' (' . basename($e->getFile())
                    . ':' . $e->getLine() . ')',
            ]);
        }

        $done = $job['stage'] === 'done';

        if ($done) {
            if (!$job['dry_run']) {
                switch_to_blog($job['target']);
                flush_rewrite_rules(false);
                restore_current_blog();
            }
            $log[] = $job['warnings']
                ? sprintf('%d thing(s) need a look — search the log for WARNING.',
                    $job['warnings'])
                : 'No warnings.';
            delete_site_option(self::JOB);
        } else {
            update_site_option(self::JOB, $job);
        }

        wp_send_json_success([
            'done' => $done,
            'stage' => $job['stage'],
            'counts' => $counts,
            'log' => $log,
        ]);
    }

    /** @return array{0:array,1:array<string>,2:string} job, log, counts */
    private function step(array $job): array
    {
        switch ($job['stage']) {
            case 'acf':
                return $this->stage_acf($job);
            case 'terms':
                return $this->stage_terms($job);
            case 'posts':
                return $this->stage_posts($job);
            case 'fixups':
                return $this->stage_fixups($job);
            case 'options':
                return $this->stage_options($job);
            case 'plugins':
                return $this->stage_plugins($job);
        }

        $job['stage'] = 'done';
        return [$job, [], ''];
    }

    // ───────────────────────────────────────────────────────────── stages ──

    private function stage_acf(array $job): array
    {
        $log = [];

        if (!$job['acf_groups'] && !$job['acf_post_types']) {
            $log[] = 'ACF: skipped.';
        } elseif (!function_exists('acf_get_field_groups')) {
            $log[] = 'WARNING  ACF is not loaded; field groups not copied.';
            $job['warnings']++;
        } else {
            $log = array_merge($log, $this->copy_acf($job));
        }

        $job['stage'] = 'terms';
        $job['queue'] = $job['taxonomies'];
        $job['cursor'] = 0;

        return [$job, $log, ''];
    }

    /**
     * Field groups, and the post types and taxonomies ACF itself registers.
     *
     * Through ACF's own export and import functions rather than by copying
     * the acf-field-group and acf-field posts by hand. A field group is a
     * tree -- a repeater's sub-fields are child posts of the field, which is
     * a child post of the group -- and acf_import_field_group already knows
     * how to rebuild that and how to recognise a group it has seen before by
     * its key. Copying the rows would mean reimplementing both.
     */
    private function copy_acf(array &$job): array
    {
        $log = [];
        $payload = ['groups' => [], 'post_types' => [], 'taxonomies' => []];

        switch_to_blog($job['source']);
        $this->reset_acf_cache();

        if ($job['acf_groups']) {
            foreach (acf_get_field_groups() as $group) {
                // A group whose fields live in PHP or in acf-json is already
                // on every blog in the network: it is registered in code, not
                // stored in this blog's database. Copying it would write a
                // database copy that then shadows the file.
                if (!empty($group['local'])) {
                    $log[] = sprintf('  skip  field group "%s" (registered in %s, already network-wide)',
                        $group['title'], $group['local']);
                    continue;
                }
                $group['fields'] = acf_get_fields($group);
                $payload['groups'][] = acf_prepare_field_group_for_export($group);
            }
        }

        if ($job['acf_post_types'] && function_exists('acf_get_internal_post_type_posts')) {
            foreach (['acf-post-type' => 'post_types', 'acf-taxonomy' => 'taxonomies'] as $type => $bucket) {
                foreach (acf_get_internal_post_type_posts($type) as $item) {
                    if (!empty($item['local'])) {
                        continue;
                    }
                    $payload[$bucket][] = acf_prepare_internal_post_type_for_export($item, $type);
                }
            }
        } elseif ($job['acf_post_types']) {
            $log[] = 'WARNING  this ACF is older than 6.1, so it cannot register '
                . 'post types — nothing to copy for that option.';
            $job['warnings']++;
        }

        restore_current_blog();

        $counts = sprintf('%d field group(s), %d post type(s), %d taxonomy(ies)',
            count($payload['groups']),
            count($payload['post_types']),
            count($payload['taxonomies']));

        if ($job['dry_run']) {
            $log[] = 'ACF: would import ' . $counts . '.';
            foreach ($payload['groups'] as $g) {
                $log[] = sprintf('  would import  field group "%s" (%s, %d field(s))',
                    $g['title'], $g['key'], count($g['fields'] ?? []));
            }
            foreach ($payload['post_types'] as $p) {
                $log[] = sprintf('  would import  post type "%s"', $p['post_type'] ?? '?');
            }
            foreach ($payload['taxonomies'] as $t) {
                $log[] = sprintf('  would import  taxonomy "%s"', $t['taxonomy'] ?? '?');
            }
            return $log;
        }

        switch_to_blog($job['target']);
        $this->reset_acf_cache();

        foreach ($payload['post_types'] as $item) {
            acf_import_internal_post_type($item, 'acf-post-type');
            $log[] = sprintf('  post type     %s', $item['post_type'] ?? '?');
        }
        foreach ($payload['taxonomies'] as $item) {
            acf_import_internal_post_type($item, 'acf-taxonomy');
            $log[] = sprintf('  taxonomy      %s', $item['taxonomy'] ?? '?');
        }
        foreach ($payload['groups'] as $group) {
            acf_import_field_group($group);
            $log[] = sprintf('  field group   %s (%s)', $group['title'], $group['key']);
        }

        $this->reset_acf_cache();
        restore_current_blog();

        $log[] = 'ACF: imported ' . $counts . '.';

        return $log;
    }

    private function stage_terms(array $job): array
    {
        $log = [];

        if ($job['cursor'] >= count($job['queue'])) {
            $job['stage'] = 'posts';
            $job['queue'] = $job['post_types'];
            $job['cursor'] = 0;
            return [$job, $log, ''];
        }

        $tax = $job['queue'][$job['cursor']];
        $job['cursor']++;

        switch_to_blog($job['source']);
        $exists = taxonomy_exists($tax);
        $terms = [];
        if ($exists) {
            $raw = get_terms([
                'taxonomy' => $tax,
                'hide_empty' => false,
                'orderby' => 'parent',
                'order' => 'ASC',
            ]);
            if (!is_wp_error($raw)) {
                foreach ($raw as $t) {
                    $terms[] = [
                        'term_id' => (int) $t->term_id,
                        'name' => $t->name,
                        'slug' => $t->slug,
                        'description' => $t->description,
                        'parent' => (int) $t->parent,
                        'meta' => get_term_meta($t->term_id),
                    ];
                }
            }
        }
        restore_current_blog();

        if (!$exists) {
            $log[] = sprintf('WARNING  taxonomy "%s" is not registered on the source; skipped.', $tax);
            $job['warnings']++;
            return [$job, $log, $this->counts($job)];
        }

        if ($job['dry_run']) {
            $log[] = sprintf('terms  %-20s would copy %d', $tax, count($terms));
            return [$job, $log, $this->counts($job)];
        }

        switch_to_blog($job['target']);

        if (!taxonomy_exists($tax)) {
            // Registered by a theme or plugin that is not active here yet, or
            // by an ACF taxonomy that this run has not reached. Terms in an
            // unregistered taxonomy are invisible to WordPress, so say so
            // rather than writing rows nobody will ever see.
            restore_current_blog();
            $log[] = sprintf('WARNING  taxonomy "%s" is not registered on the target; '
                . 'terms not copied. Copy the ACF taxonomies or activate the '
                . 'plugin that registers it, then run again.', $tax);
            $job['warnings']++;
            return [$job, $log, $this->counts($job)];
        }

        // Two passes: every term first, then the parents, because a child can
        // appear before its parent and wp_insert_term rejects a parent id that
        // is not there yet.
        $made = 0;
        foreach ($terms as $t) {
            $found = get_term_by('slug', $t['slug'], $tax);
            if ($found) {
                wp_update_term($found->term_id, $tax, [
                    'name' => $t['name'],
                    'description' => $t['description'],
                ]);
                $new_id = (int) $found->term_id;
            } else {
                $res = wp_insert_term($t['name'], $tax, [
                    'slug' => $t['slug'],
                    'description' => $t['description'],
                ]);
                if (is_wp_error($res)) {
                    $log[] = sprintf('WARNING  term "%s" (%s): %s',
                        $t['name'], $tax, $res->get_error_message());
                    $job['warnings']++;
                    continue;
                }
                $new_id = (int) $res['term_id'];
                $made++;
            }

            $job['map_terms'][$t['term_id']] = $new_id;

            foreach ($t['meta'] as $key => $values) {
                delete_term_meta($new_id, $key);
                foreach ($values as $v) {
                    add_term_meta($new_id, $key, maybe_unserialize($v));
                }
            }
        }

        foreach ($terms as $t) {
            if (!$t['parent'] || empty($job['map_terms'][$t['term_id']])) {
                continue;
            }
            $parent = $job['map_terms'][$t['parent']] ?? 0;
            if ($parent) {
                wp_update_term($job['map_terms'][$t['term_id']], $tax, ['parent' => $parent]);
            }
        }

        restore_current_blog();

        $log[] = sprintf('terms  %-20s %d copied (%d new)', $tax, count($terms), $made);

        return [$job, $log, $this->counts($job)];
    }

    private function stage_posts(array $job): array
    {
        $log = [];

        if ($job['cursor'] >= count($job['queue'])) {
            $job['stage'] = 'fixups';
            return [$job, $log, ''];
        }

        $entry = $job['queue'][$job['cursor']];

        // A queue entry starts life as a post type name and becomes an array
        // once we have asked the source for its IDs.
        if (!is_array($entry)) {
            $statuses = $job['drafts']
                ? ['publish', 'draft', 'pending', 'private', 'future']
                : ['publish'];

            switch_to_blog($job['source']);
            $ids = get_posts([
                'post_type' => $entry,
                'post_status' => $statuses,
                'posts_per_page' => -1,
                'fields' => 'ids',
                'orderby' => 'ID',
                'order' => 'ASC',
                'suppress_filters' => true,
            ]);
            restore_current_blog();

            $entry = ['type' => $entry, 'ids' => array_map('intval', $ids), 'at' => 0];
            $job['queue'][$job['cursor']] = $entry;

            // Menu items cannot be matched the way everything else is: a
            // nav_menu_item's post_name is empty or a bare number, not a
            // slug, so there is nothing stable to recognise one by and a
            // second run would simply add every item again. Menus are
            // replaced instead -- the old items go, the copied ones arrive.
            if ($entry['type'] === 'nav_menu_item' && !$job['dry_run']) {
                $removed = $this->empty_menus($job['target']);
                if ($removed) {
                    $log[] = sprintf('menus  %d existing menu item(s) removed from '
                        . 'the target before copying', $removed);
                }
            }

            $log[] = sprintf('%s  %-20s %d to copy',
                $job['dry_run'] ? 'would' : 'posts', $entry['type'], count($entry['ids']));

            if ($job['dry_run'] || !$entry['ids']) {
                $job['cursor']++;
                return [$job, $log, $this->counts($job)];
            }

            return [$job, $log, $this->counts($job)];
        }

        $slice = array_slice($entry['ids'], $entry['at'], self::BATCH);

        foreach ($slice as $src_id) {
            $snap = $this->read_post($job, $src_id);
            if (!$snap) {
                continue;
            }

            $new_id = $this->write_post($job, $snap);
            if (is_wp_error($new_id)) {
                $log[] = sprintf('WARNING  %s #%d "%s": %s',
                    $snap['data']['post_type'], $src_id,
                    $snap['data']['post_title'], $new_id->get_error_message());
                $job['warnings']++;
                continue;
            }

            $job['map_posts'][$src_id] = $new_id;
            if ($snap['parent']) {
                $job['parents'][$src_id] = $snap['parent'];
            }
            if ($snap['attachments']) {
                foreach ($snap['attachments'] as $old => $new) {
                    $job['map_attachments'][$old] = $new;
                }
            }
        }

        $entry['at'] += count($slice);
        $job['queue'][$job['cursor']] = $entry;

        $log[] = sprintf('posts  %-20s %d/%d',
            $entry['type'], min($entry['at'], count($entry['ids'])), count($entry['ids']));

        if ($entry['at'] >= count($entry['ids'])) {
            $job['cursor']++;
        }

        return [$job, $log, $this->counts($job)];
    }

    /**
     * The passes that can only run once everything has an ID on the target.
     *
     * post_parent, menu items, and -- when asked -- attachment ids sitting in
     * post meta. None of these can be done while copying, because the thing
     * being pointed at may not have been copied yet.
     */
    private function stage_fixups(array $job): array
    {
        $log = [];

        if ($job['dry_run'] || !$job['map_posts']) {
            $job['stage'] = 'options';
            return [$job, $log, ''];
        }

        switch_to_blog($job['target']);

        $fixed = 0;
        foreach ($job['parents'] as $src_id => $src_parent) {
            $child = $job['map_posts'][$src_id] ?? 0;
            $parent = $job['map_posts'][$src_parent] ?? 0;
            if (!$child) {
                continue;
            }
            if (!$parent) {
                $log[] = sprintf('WARNING  post %d kept at the top level: its parent '
                    . '(%d on the source) was not part of this run.', $child, $src_parent);
                $job['warnings']++;
                continue;
            }
            wp_update_post(['ID' => $child, 'post_parent' => $parent]);
            $fixed++;
        }
        if ($job['parents']) {
            $log[] = sprintf('fixups  %d parent link(s) repointed', $fixed);
        }

        $menus = $this->fix_menu_items($job);
        if ($menus) {
            $log = array_merge($log, $menus);
        }

        if ($job['remap_attachment_meta'] && $job['map_attachments']) {
            $log = array_merge($log, $this->remap_attachment_meta($job));
        }

        restore_current_blog();

        $job['stage'] = 'options';

        return [$job, $log, ''];
    }

    private function stage_options(array $job): array
    {
        $log = [];

        if (!$job['options']) {
            $job['stage'] = 'plugins';
            return [$job, $log, ''];
        }

        switch_to_blog($job['source']);
        $found = $this->match_options($job['options']);
        restore_current_blog();

        if (!$found) {
            $log[] = 'options  nothing matched.';
            $job['stage'] = 'plugins';
            return [$job, $log, ''];
        }

        if ($job['dry_run']) {
            $log[] = sprintf('options  would copy %d:', count($found));
            foreach (array_keys($found) as $key) {
                $log[] = '  would set  ' . $key;
            }
            $job['stage'] = 'plugins';
            return [$job, $log, ''];
        }

        switch_to_blog($job['target']);
        $remapped = 0;
        foreach ($found as $key => $value) {
            // theme_mods_<theme> carries nav_menu_locations, which maps a
            // theme location to a TERM id. Copied as it stands, every
            // location on the new blog would point at one of the source's
            // term ids and so at no menu at all -- menus copied, and none
            // of them showing up anywhere.
            if (strpos($key, 'theme_mods_') === 0
                && is_array($value)
                && !empty($value['nav_menu_locations'])
                && is_array($value['nav_menu_locations'])) {
                foreach ($value['nav_menu_locations'] as $location => $term_id) {
                    $mapped = $job['map_terms'][(int) $term_id] ?? 0;
                    if ($mapped) {
                        $value['nav_menu_locations'][$location] = $mapped;
                        $remapped++;
                    } else {
                        unset($value['nav_menu_locations'][$location]);
                    }
                }
            }

            update_option($key, $value);
        }
        restore_current_blog();

        $log[] = sprintf('options  %d copied.', count($found));
        if ($remapped) {
            $log[] = sprintf('options  %d menu location(s) repointed at the copied menus',
                $remapped);
        }
        $log[] = 'WARNING  option values are copied as they are. Any post or '
            . 'attachment ID inside one still points at the source site.';
        $job['warnings']++;

        $job['stage'] = 'plugins';

        return [$job, $log, ''];
    }

    private function stage_plugins(array $job): array
    {
        $log = [];

        if (!$job['plugins']) {
            $job['stage'] = 'done';
            return [$job, $log, ''];
        }

        switch_to_blog($job['source']);
        $active = (array) get_option('active_plugins', []);
        $template = get_option('template');
        $stylesheet = get_option('stylesheet');
        restore_current_blog();

        require_once ABSPATH . 'wp-admin/includes/plugin.php';

        $installed = array_keys(get_plugins());
        $have = array_values(array_intersect($active, $installed));
        $missing = array_values(array_diff($active, $installed));

        if ($job['dry_run']) {
            $log[] = sprintf('plugins  would activate %d, would switch theme to "%s"',
                count($have), $stylesheet);
            foreach ($have as $file) {
                $log[] = '  would activate  ' . $file;
            }
        } else {
            switch_to_blog($job['target']);

            // activate_plugins rather than writing active_plugins directly,
            // so each plugin's activation hook runs and it gets to create its
            // own tables and defaults on this blog.
            $res = activate_plugins($have, '', false, true);
            if (is_wp_error($res)) {
                $log[] = 'WARNING  activating plugins: ' . $res->get_error_message();
                $job['warnings']++;
            }

            if ($template && $stylesheet) {
                switch_theme($stylesheet);
            }

            restore_current_blog();

            $log[] = sprintf('plugins  %d activated, theme switched to "%s"',
                count($have), $stylesheet);
        }

        foreach ($missing as $file) {
            $log[] = sprintf('WARNING  plugin "%s" is active on the source but '
                . 'not installed on this network.', $file);
            $job['warnings']++;
        }

        $job['stage'] = 'done';

        return [$job, $log, ''];
    }

    // ───────────────────────────────────────────────────────── post copying ──

    /** Everything about one source post, as plain arrays. */
    private function read_post(array $job, int $id): ?array
    {
        switch_to_blog($job['source']);

        $post = get_post($id);
        if (!$post) {
            restore_current_blog();
            return null;
        }

        $snap = [
            'src_id' => $id,
            'parent' => (int) $post->post_parent,
            'data' => [
                'post_title' => $post->post_title,
                'post_name' => $post->post_name,
                'post_content' => $post->post_content,
                'post_excerpt' => $post->post_excerpt,
                'post_status' => $post->post_status,
                'post_type' => $post->post_type,
                'post_date' => $post->post_date,
                'post_date_gmt' => $post->post_date_gmt,
                'post_author' => (int) $post->post_author,
                'menu_order' => (int) $post->menu_order,
                'comment_status' => $post->comment_status,
                'ping_status' => $post->ping_status,
                'post_password' => $post->post_password,
                'post_mime_type' => $post->post_mime_type,
            ],
            'meta' => get_post_meta($id),
            'terms' => [],
            'thumb' => 0,
            'attachments' => [],
        ];

        foreach (get_object_taxonomies($post->post_type) as $tax) {
            $slugs = wp_get_object_terms($id, $tax, ['fields' => 'slugs']);
            if (!is_wp_error($slugs) && $slugs) {
                $snap['terms'][$tax] = $slugs;
            }
        }

        if ($job['attachments']) {
            $snap['thumb'] = (int) get_post_thumbnail_id($id);
        }

        restore_current_blog();

        // The featured image is copied before the post that wants it, so that
        // _thumbnail_id can be written with the new ID in one go.
        if ($snap['thumb']) {
            $new = $this->copy_attachment($job, $snap['thumb']);
            if ($new) {
                $snap['attachments'][$snap['thumb']] = $new;
                $snap['meta']['_thumbnail_id'] = [(string) $new];
            }
        }

        return $snap;
    }

    /** Writes one snapshot to the target, updating a slug match in place. */
    private function write_post(array $job, array $snap)
    {
        switch_to_blog($job['target']);

        $args = $snap['data'];

        // The source's author ID is a network user ID, which is the same
        // number everywhere -- but the user may not be a member of the target
        // blog, and WordPress will not show a post whose author is a stranger
        // in the admin list. Falls back to whoever is running this.
        if (!$args['post_author'] || !is_user_member_of_blog($args['post_author'], $job['target'])) {
            $args['post_author'] = get_current_user_id();
        }

        $existing = $this->find_by_slug($args['post_name'], $args['post_type']);
        if ($existing) {
            $args['ID'] = $existing;
            $new_id = wp_update_post(wp_slash($args), true);
        } else {
            $new_id = wp_insert_post(wp_slash($args), true);
        }

        if (is_wp_error($new_id)) {
            restore_current_blog();
            return $new_id;
        }

        $new_id = (int) $new_id;

        foreach ($snap['meta'] as $key => $values) {
            if (in_array($key, self::META_SKIP, true)) {
                continue;
            }
            delete_post_meta($new_id, $key);
            foreach ((array) $values as $value) {
                add_post_meta($new_id, $key, maybe_unserialize($value));
            }
        }

        foreach ($snap['terms'] as $tax => $slugs) {
            if (taxonomy_exists($tax)) {
                wp_set_object_terms($new_id, $slugs, $tax, false);
            }
        }

        restore_current_blog();

        return $new_id;
    }

    /**
     * Deletes every menu item on a blog, leaving the menus themselves.
     *
     * See the note in stage_posts: menu items have no stable slug, so the
     * only way to copy a menu twice without doubling it is to clear first.
     * The nav_menu terms stay, because they do have slugs and are matched
     * like any other term.
     *
     * @return int how many were removed
     */
    private function empty_menus(int $blog_id): int
    {
        switch_to_blog($blog_id);

        $ids = get_posts([
            'post_type' => 'nav_menu_item',
            'post_status' => 'any',
            'posts_per_page' => -1,
            'fields' => 'ids',
            'suppress_filters' => true,
        ]);

        foreach ($ids as $id) {
            wp_delete_post($id, true);
        }

        restore_current_blog();

        return count($ids);
    }

    /** The post on the current blog with this slug and type, or 0. */
    private function find_by_slug(string $slug, string $type): int
    {
        global $wpdb;

        if ($slug === '') {
            return 0;
        }

        return (int) $wpdb->get_var($wpdb->prepare(
            "SELECT ID FROM {$wpdb->posts}
             WHERE post_name = %s AND post_type = %s
               AND post_status NOT IN ('trash', 'auto-draft')
             ORDER BY ID ASC LIMIT 1",
            $slug,
            $type
        ));
    }

    /**
     * Duplicates one attachment, file and all, into the target's uploads.
     *
     * Each blog in a multisite network has its own uploads folder, so an
     * attachment row copied on its own would point at a path the target
     * cannot serve. The file is copied too, and the metadata regenerated so
     * the target builds its own thumbnail sizes.
     *
     * @return int The attachment ID on the target, or 0.
     */
    private function copy_attachment(array $job, int $src_id): int
    {
        if (isset($job['map_attachments'][$src_id])) {
            return (int) $job['map_attachments'][$src_id];
        }
        if ($job['dry_run']) {
            return 0;
        }

        switch_to_blog($job['source']);
        $post = get_post($src_id);
        $file = get_attached_file($src_id);
        $meta = $post ? get_post_meta($src_id) : [];
        restore_current_blog();

        if (!$post || !$file || !file_exists($file)) {
            return 0;
        }

        switch_to_blog($job['target']);

        $existing = $this->find_by_slug($post->post_name, 'attachment');
        if ($existing) {
            restore_current_blog();
            return $existing;
        }

        $uploads = wp_upload_dir();
        if (!empty($uploads['error'])) {
            restore_current_blog();
            return 0;
        }

        $dest = $uploads['path'] . '/' . wp_unique_filename($uploads['path'], basename($file));
        if (!@copy($file, $dest)) {
            restore_current_blog();
            return 0;
        }

        $new_id = wp_insert_attachment([
            'post_title' => $post->post_title,
            'post_name' => $post->post_name,
            'post_content' => $post->post_content,
            'post_excerpt' => $post->post_excerpt,
            'post_status' => 'inherit',
            'post_mime_type' => $post->post_mime_type,
            'post_author' => get_current_user_id(),
        ], $dest, 0, true);

        if (is_wp_error($new_id)) {
            @unlink($dest);
            restore_current_blog();
            return 0;
        }

        $new_id = (int) $new_id;

        // Alt text and any ACF fields on the attachment. _wp_attached_file
        // and _wp_attachment_metadata belong to the new file, not the old
        // one, so they are left to wp_generate_attachment_metadata.
        foreach ($meta as $key => $values) {
            if (in_array($key, ['_wp_attached_file', '_wp_attachment_metadata'], true)
                || in_array($key, self::META_SKIP, true)) {
                continue;
            }
            delete_post_meta($new_id, $key);
            foreach ((array) $values as $value) {
                add_post_meta($new_id, $key, maybe_unserialize($value));
            }
        }

        require_once ABSPATH . 'wp-admin/includes/image.php';
        wp_update_attachment_metadata(
            $new_id,
            wp_generate_attachment_metadata($new_id, $dest)
        );

        restore_current_blog();

        return $new_id;
    }

    // ───────────────────────────────────────────────────────────── fixups ──

    /**
     * Points copied menu items at the copied things they describe.
     *
     * A nav_menu_item is a post whose meta says what it links to:
     * _menu_item_object_id is a post ID or a term ID depending on
     * _menu_item_type, and _menu_item_menu_item_parent is another menu item's
     * post ID. All three are per-blog numbers.
     *
     * @return array<string> log lines
     */
    private function fix_menu_items(array $job): array
    {
        $items = [];
        foreach ($job['map_posts'] as $src_id => $new_id) {
            if (get_post_type($new_id) === 'nav_menu_item') {
                $items[$src_id] = $new_id;
            }
        }

        if (!$items) {
            return [];
        }

        $log = [];
        $ok = 0;
        $lost = 0;

        foreach ($items as $src_id => $new_id) {
            $parent = (int) get_post_meta($new_id, '_menu_item_menu_item_parent', true);
            if ($parent && isset($items[$parent])) {
                update_post_meta($new_id, '_menu_item_menu_item_parent', $items[$parent]);
            }

            $type = get_post_meta($new_id, '_menu_item_type', true);
            $object = (int) get_post_meta($new_id, '_menu_item_object_id', true);

            if (!$object) {
                continue;
            }

            if ($type === 'taxonomy') {
                $mapped = $job['map_terms'][$object] ?? 0;
            } elseif ($type === 'post_type') {
                $mapped = $job['map_posts'][$object] ?? 0;
            } else {
                // A custom link has no object to repoint.
                continue;
            }

            if ($mapped) {
                update_post_meta($new_id, '_menu_item_object_id', $mapped);
                $ok++;
            } else {
                $lost++;
            }
        }

        $log[] = sprintf('fixups  %d menu item(s): %d repointed', count($items), $ok);

        if ($lost) {
            $log[] = sprintf('WARNING  %d menu item(s) point at something that was '
                . 'not part of this run, so they still hold source IDs. Add those '
                . 'post types or taxonomies and run again, or fix the menu by hand.',
                $lost);
        }

        return $log;
    }

    /**
     * Rewrites attachment IDs sitting in post meta.
     *
     * Narrow on purpose: a value is only touched when it is exactly the ID of
     * an attachment this run copied, or a list of such IDs. That is why it is
     * behind its own checkbox -- a numeric meta value that happens to equal
     * an attachment ID would be rewritten too, and only you know whether any
     * of your fields are like that.
     *
     * @return array<string> log lines
     */
    private function remap_attachment_meta(array $job): array
    {
        $map = $job['map_attachments'];
        $changed = 0;

        foreach ($job['map_posts'] as $new_id) {
            foreach (get_post_meta($new_id) as $key => $values) {
                if (in_array($key, self::META_SKIP, true) || $key === '_thumbnail_id') {
                    continue;
                }

                foreach ((array) $values as $raw) {
                    $value = maybe_unserialize($raw);

                    if (is_scalar($value) && isset($map[(int) $value])
                        && (string) (int) $value === (string) $value) {
                        update_post_meta($new_id, $key, $map[(int) $value], $raw);
                        $changed++;
                        continue;
                    }

                    if (is_array($value)) {
                        $new = $value;
                        $hit = false;
                        foreach ($new as $i => $item) {
                            if (is_scalar($item) && isset($map[(int) $item])
                                && (string) (int) $item === (string) $item) {
                                $new[$i] = $map[(int) $item];
                                $hit = true;
                            }
                        }
                        if ($hit) {
                            update_post_meta($new_id, $key, $new, $raw);
                            $changed++;
                        }
                    }
                }
            }
        }

        return [sprintf('fixups  %d meta value(s) repointed at copied attachments', $changed)];
    }

    // ────────────────────────────────────────────────────────────── helpers ──

    private function guard(): void
    {
        if (!current_user_can(self::CAP)) {
            wp_send_json_error(['message' => 'Not allowed.'], 403);
        }
        if (!check_ajax_referer(self::NONCE, '_wpnonce', false)) {
            wp_send_json_error(['message' => 'This page went stale. Reload and try again.'], 403);
        }
    }

    private function post_bool(string $key): bool
    {
        return !empty($_POST[$key]);
    }

    /** @return array<string> */
    private function post_list(string $key): array
    {
        $raw = $_POST[$key] ?? [];
        if (!is_array($raw)) {
            $raw = [$raw];
        }

        $out = [];
        foreach ($raw as $value) {
            $value = sanitize_key(wp_unslash((string) $value));
            if ($value !== '') {
                $out[] = $value;
            }
        }

        return array_values(array_unique($out));
    }

    /** @return array<string> the option patterns, denied ones removed */
    private function option_patterns(): array
    {
        $raw = (string) wp_unslash($_POST['options'] ?? '');
        $out = [];

        foreach (preg_split('/[\r\n,]+/', $raw) as $line) {
            $line = trim($line);
            if ($line === '' || !$this->option_allowed(rtrim($line, '*'))) {
                continue;
            }
            // Only the characters an option name can contain, plus the one
            // trailing star this understands.
            if (!preg_match('/^[A-Za-z0-9_\-]+\*?$/', $line)) {
                continue;
            }
            $out[] = $line;
        }

        return array_values(array_unique($out));
    }

    private function option_allowed(string $name): bool
    {
        foreach (self::OPTION_DENY as $deny) {
            if ($name === $deny || strpos($name, $deny) === 0 || strpos($deny, $name) === 0) {
                return false;
            }
        }

        return $name !== '';
    }

    /**
     * The current blog's options matching these patterns.
     *
     * Read straight out of the table rather than through get_option, so that
     * a pattern can find options nobody has named in code, and so that a
     * filter on the source blog cannot change what gets copied.
     *
     * @param array<string> $patterns
     * @return array<string,mixed>
     */
    private function match_options(array $patterns): array
    {
        global $wpdb;

        $where = [];
        $args = [];

        foreach ($patterns as $pattern) {
            if (substr($pattern, -1) === '*') {
                $where[] = 'option_name LIKE %s';
                $args[] = $wpdb->esc_like(rtrim($pattern, '*')) . '%';
            } else {
                $where[] = 'option_name = %s';
                $args[] = $pattern;
            }
        }

        if (!$where) {
            return [];
        }

        $rows = $wpdb->get_results($wpdb->prepare(
            "SELECT option_name, option_value FROM {$wpdb->options}
             WHERE " . implode(' OR ', $where),
            $args
        ));

        $out = [];
        foreach ((array) $rows as $row) {
            if (!$this->option_allowed($row->option_name)) {
                continue;
            }
            $out[$row->option_name] = maybe_unserialize($row->option_value);
        }

        ksort($out);

        return $out;
    }

    private function counts(array $job): string
    {
        return sprintf('%d post(s), %d term(s) so far',
            count($job['map_posts']), count($job['map_terms']));
    }

    /**
     * Empties ACF's in-memory stores.
     *
     * ACF caches field groups and fields for the length of the request. Those
     * caches are not keyed by blog, so a group read before a switch_to_blog
     * is still sitting there afterwards and will be handed back as though it
     * belonged to the blog we have moved to.
     */
    private function reset_acf_cache(): void
    {
        if (!function_exists('acf_get_store')) {
            return;
        }

        foreach (['field-groups', 'fields', 'post-types', 'taxonomies', 'options-pages'] as $name) {
            $store = acf_get_store($name);
            if ($store) {
                $store->reset();
            }
        }
    }
}

DL_Site_Cloner::boot();
