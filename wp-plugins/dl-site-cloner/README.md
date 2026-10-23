# DL Site Cloner

Copies structure and content from one site in the network to another. Written
for standing up a new regional blog — EU, AU — against the UK one.

**Install:** drop the `dl-site-cloner` folder into `wp-content/plugins/`, then
network-activate it. It does nothing at all unless a super admin opens its
screen, which is **Network Admin → Settings → Site Cloner**.

**It requires multisite** and bails out silently otherwise.

---

## Read this first: three different things look like "the new blog is empty"

Open the screen, pick the two sites and press **Compare the two sites**. It
writes nothing and it tells you which of these you have, because the fix is
different for each.

**1. The post type isn't registered on the new blog.**
Compare shows `not registered` next to it. Post types and taxonomies declared
with `register_post_type()` live in your theme or a plugin, not in the
database — so there is nothing to copy, and copying content will not help. The
new blog needs the theme and the plugins active. Tick **Active plugins and
theme** and run; or do it by hand from the site's own admin.

**2. The post type is registered but holds nothing.**
Compare shows `yes / 0`. This is the case the cloner is for: pick the type
under **Content** and run.

**3. The field groups are missing.**
Depends on where they live:

| Where your field groups are | What happens |
| --- | --- |
| In the database (created in the ACF admin) | Copied. This is the normal case. |
| In `acf-json/` in the theme | Already on every blog — ACF loads them from the files. The log says `skip … already network-wide`. |
| In PHP via `acf_add_local_field_group()` | Same: already everywhere, skipped. |

If Compare says the UK site has 40 field groups and the new one has 40 too,
they are file-based and there was never anything to copy.

---

## Suggested order for a brand-new blog

Each of these is one run. Doing it in stages means a mistake costs one stage,
not all of it — and some steps genuinely depend on an earlier one.

1. **Active plugins and theme**, on its own.
   Nothing else can work before this: a post type that isn't registered can't
   hold posts, and a taxonomy that isn't registered can't hold terms.
   Afterwards, press Compare again — most of the "missing" list usually
   disappears here.

2. **ACF field groups + ACF post types and taxonomies.**
   Post types before content, for the same reason as above. If ACF registers
   any of your types — rather than the theme — this is the step that creates
   them.

3. **Taxonomy terms.**
   Before the content, so that posts have something to be filed under.
   Preselected: `club_category`, `nav_menu`.

4. **Content**, one or two post types at a time.
   Preselected: `page`, `nav_menu_item`. Tick **Copy featured images** if you
   want the pictures as well as the words.

5. **Options**, last.
   `theme_mods_*` holds which menu goes in which theme location, and that is
   stored as term IDs — so it only makes sense once the menus from step 3
   exist. The cloner repoints them for you, but only in the same run or a
   later one.

**Always run with Dry run ticked first.** It reports every single thing it
would do and writes nothing.

---

## What it matches on, and why re-running is safe

Nothing is matched by ID, because a post ID is only unique within one blog.
Instead:

| | matched by |
| --- | --- |
| ACF field groups | their ACF key (`group_abc123`) |
| ACF post types, taxonomies | their key |
| Terms | slug, within the taxonomy |
| Posts, pages, attachments | `post_name` (the slug), within the post type |
| Menu items | nothing — see below |

So a second run **updates** what the first one made rather than making another
copy. That is what makes it safe to fix one field group and run the whole
thing again.

Existing content on the target with a matching slug is **overwritten**. That
is the point, but it means a page someone has edited on the new blog will lose
those edits if the same slug exists on the source.

**Menus are the exception.** A `nav_menu_item` has no usable slug — its
`post_name` is empty or a bare number — so there is nothing stable to
recognise one by. Menu items are therefore *replaced*: every existing menu
item on the target is deleted before the copied ones arrive. The menus
themselves (the `nav_menu` terms) are matched by slug like anything else.

---

## What it does not do

**It does not rewrite IDs inside post meta**, with two exceptions. An ACF
relationship or post-object field pointing at post 412 on the UK site will
still say 412 on the new blog, where that is a different post or no post at
all. The cloner cannot know which numeric meta values are references, so it
does not guess. Check the log for `WARNING`.

The two exceptions:

- **Featured images.** With *Copy featured images* on, the attachment and its
  file are duplicated into the target's own uploads folder and `_thumbnail_id`
  is repointed. Each blog in a multisite has a separate uploads directory, so
  copying the row without the file would give you a broken image.
- **Attachment IDs in meta**, if you tick the second box. Narrow on purpose:
  it only touches a meta value that is *exactly* the ID of an attachment
  copied in this same run, or an array of such IDs. It's opt-in because a
  numeric field of yours that happens to equal one of those IDs would be
  rewritten too — only you know whether you have one.

**It does not copy users.** Author IDs are network-wide so the number is
valid, but if the author isn't a member of the target blog the post is
reassigned to whoever is running the clone, because WordPress hides posts
whose author is a stranger to the blog.

**It refuses some options whatever you type.** `siteurl` and `home` identify
the site and a copy would take the new blog offline; `active_plugins`,
`template` and `stylesheet` have their own step, which activates properly so
each plugin's activation hook runs; `rewrite_rules` and the transients are
derived state WordPress rebuilds. The full list is `OPTION_DENY` in the
plugin.

---

## Notes on how it works

**One job at a time**, held in a network option and stepped through by AJAX,
25 posts per request. A few thousand posts does not have to fit inside one PHP
request, and nothing is lost to a timeout — though closing the tab mid-run
leaves the job half-done, and the next press of Run starts a fresh one.

**Nothing holds a WordPress object across a `switch_to_blog`.** Each step
reads the source into plain arrays, restores the blog, then writes. Object
caches and ACF's own in-memory stores are not all keyed by blog, so an object
read before a switch will happily answer questions about the wrong site
afterwards. ACF's stores are explicitly reset around each switch for the same
reason.

**Field groups go through ACF's own export and import functions** rather than
by copying the `acf-field-group` and `acf-field` rows. A field group is a tree
— a repeater's sub-fields are child posts of the field, which is a child post
of the group — and `acf_import_field_group()` already knows how to rebuild
that and how to recognise a group by its key. Copying rows would mean
reimplementing both, badly.

**Plugins are activated, not written.** The step calls `activate_plugins()` on
the target so each plugin's activation hook runs and it gets to create its own
tables and defaults for that blog. Writing the `active_plugins` option
directly would leave plugins listed as on but never initialised.

---

## After the clone, for the DriveLife app

The blog IDs are compiled into the API. Once the EU site is populated:

- **`php-api/helpers.php`** — set `DL_BLOG_EU` (currently `0`) to the new
  blog's ID. That is the only change needed here: `dl_regions()` already has
  the `EU` entry, pointing at the constant, with `GB` as its fallback and its
  country list filled in. `dl_blog_order()` skips any region whose blog is
  `0`, which is why the EU site is invisible to the app until you set it.

- **`drivelife-account/lib/regions.ts`** — add an `eu` entry to `REGIONS`.
  This one really is missing: the dashboard only knows `uk` and `us`, so
  `resolveRegion()` falls back to UK for anything else and the EU site has no
  currency, label or ticketing config until you add it.

Do these after the clone, not before. While `DL_BLOG_EU` is `0` the app
cannot see a half-populated site, which is what you want during the copy.
