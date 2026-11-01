# Global groups — design

Scene groups and marque/model groups, as **global objects** rather than
as clubs.

Nothing here is built. This is the design to agree before any of it is
coded, following on from `groups-backend-notes.md`, which assumed these
would be WordPress clubs with an ACF `kind` field. They should not be.
This document says why, what the tables look like, and how one group
reaches every user on every blog.

---

## 1. The reframe, and what it changes

The earlier plan treated a scene group as a club with a label on it.
That followed from assuming a group is **a container people fill**.

It is not. A global group is:

> a global object whose purpose is to group things that have something
> in common, which users can post into, but whose activity is mainly
> generated at our end.

Three things fall out of that, and each one points away from a club
post:

**It is a rule, not a container.** "Mazda MX-5" is not an empty room
somebody has to furnish. It is a statement about which cars, spots,
posts and owners belong together — and the app can evaluate it today
against data that already exists. A club post has no way to express
that; it only has a members list somebody typed into.

**Its contents are derived, so they must be rebuildable.** If we
generate the activity, we will get it wrong, change the weighting, add a
source, and need to regenerate. Derived data wants an index that can be
dropped and rebuilt from the sources. Content written into a WordPress
post is the opposite: it is the only copy.

**It is global, and WordPress posts cannot be.** A CPT is physically
per-site. There is no such thing as a `clubs` post that exists on every
blog — only copies that drift. Meanwhile the social tables are
*already* global: `ce_user_garage` has no `blog_id` column, and neither
does `ce_social_posts`. Global groups belong with those, not with the
CPTs.

So: custom tables. The rest of this is what they look like.

---

## 2. Why custom tables beat the alternatives

For the record, since both other options were on the table:

| Option | Why not |
| --- | --- |
| Clubs on the UK blog with a `kind` field | Pollutes the UK carevents site with JDM and MX-5 groups. This is the objection that killed it. |
| A dedicated "global" blog in the network | Keeps the WP sites clean, but buys a whole blog to hold a few dozen rows, adds a fifth `switch_to_blog` target to every cross-blog lookup, and still gives each group a post id that collides with ids on other blogs. |
| **Custom tables, no `blog_id`** | Global by construction. Nothing to synchronise, nothing to switch to, one id space. |

The decisive detail is the one above: **`ce_social_posts` has no
`blog_id` column.** I had assumed it did. It does not —
`dl_blog_scope_sql()` is only applied to the media tables
(`ce_cf_clubs_media`, `ce_cf_events_media`, `ce_cf_venues_media`) and
`dl_get_club_posts()` filters on `club_id` alone. Posts, likes,
comments, garages and users are already one network-wide pool.

Which means a global group needs no cross-blog machinery at all. It is
not a hard problem once the group stops being a post.

---

## 3. The tables

Five. House conventions throughout, matching `sql/points-ledger.sql` and
`sql/garage-likes.sql`: `ce_` prefix, `BIGINT UNSIGNED` ids, InnoDB,
`utf8mb4_unicode_ci`, no foreign keys, uniqueness enforced in the
database rather than in PHP.

**No `blog_id` on any of them.** That omission is the feature, and it
is deliberate in the same way `ce_user_garage` omits it.

A note on the name: `ce_groups`, not `ce_global_groups`. `ce_gallery_groups`
already exists and is unrelated (it is the gallery card index that
`dl-groups-refresh.php` rebuilds). `ce_groups` leaves room for user
clubs to migrate into this model later if we ever want one groups
system instead of two.

### 3.1 `ce_groups` — the group itself

```sql
CREATE TABLE IF NOT EXISTS ce_groups (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

  -- scene | marque | model. Same vocabulary as GroupKind in the app.
  kind          VARCHAR(24)  NOT NULL,

  -- The stable public identifier: 'jdm', 'mazda-mx-5'.
  --
  -- Deep links, the SEO site and share URLs all key off this rather
  -- than the numeric id, so a group can be rebuilt, merged or
  -- reseeded without breaking links already in the wild. The numeric
  -- id is internal.
  slug          VARCHAR(96)  NOT NULL,

  title         VARCHAR(191) NOT NULL,
  strapline     VARCHAR(255) NULL,
  description   TEXT         NULL,

  -- Cloudflare Images ids, handled exactly like ce_cf_clubs_media
  -- rows: stored as the id, rendered through get_cloudflare_media_url().
  cover_image   VARCHAR(191) NULL,
  logo          VARCHAR(191) NULL,

  -- draft | published | hidden.
  --
  -- This is what the ACF field was going to be for. 'draft' is a group
  -- being set up, 'published' is live everywhere, 'hidden' is retired
  -- without deleting its history.
  status        VARCHAR(16)  NOT NULL DEFAULT 'draft',

  -- Curation. Which groups lead the section, and in what order.
  is_featured   TINYINT(1)   NOT NULL DEFAULT 0,
  sort_order    INT          NOT NULL DEFAULT 0,

  -- Denormalised caches, same bargain as points_current in
  -- ce_user_meta: read on every list request, rebuildable from the
  -- link tables if they drift. A tile showing a member count must not
  -- cost a COUNT over a membership table per tile.
  member_count  INT UNSIGNED NOT NULL DEFAULT 0,
  vehicle_count INT UNSIGNED NOT NULL DEFAULT 0,
  activity_count INT UNSIGNED NOT NULL DEFAULT 0,

  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (id),

  -- One group per slug, enforced here so a careless reseed cannot
  -- create a second 'jdm' and split its history in two.
  UNIQUE KEY uniq_slug (slug),

  -- The list query: published groups of one kind, in curated order.
  KEY by_kind (kind, status, is_featured, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 3.2 `ce_group_rules` — what belongs in the group

The "something in common", made explicit. One row per clause; clauses
within a group are OR-ed.

```sql
CREATE TABLE IF NOT EXISTS ce_group_rules (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_id   BIGINT UNSIGNED NOT NULL,

  -- make | model | variant | body_type | fuel | year_range | keyword
  rule_type  VARCHAR(24)  NOT NULL,

  -- Normalised at write time: lowercase, trimmed. Matching is then an
  -- equality test on an indexed column rather than a LIKE, which is
  -- the difference between an index lookup and a scan of every
  -- vehicle in the system.
  value      VARCHAR(191) NOT NULL,

  -- Only for year_range; NULL otherwise.
  value_to   VARCHAR(191) NULL,

  -- Lets a rule be switched off without losing the record of it.
  is_active  TINYINT(1)   NOT NULL DEFAULT 1,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (id),
  UNIQUE KEY uniq_rule (group_id, rule_type, value),

  -- THE HOT INDEX, and the reason this is a table.
  --
  -- "Which groups does this Mazda MX-5 belong to?" runs every time a
  -- vehicle is added or edited and on every refresh pass. Against
  -- this index it is one lookup. Held as a JSON column on ce_groups
  -- instead, the same question means reading every group and
  -- evaluating its JSON in PHP.
  KEY by_match (rule_type, value, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

So "JDM" is six rows (`make` = nissan, toyota, mazda, subaru, honda,
mitsubishi) and "Mazda MX-5" is one (`model` = mx-5, or a `variant`
row beside it). A group with no rules is legitimate: it is a group
whose contents are curated by hand, and nothing auto-populates it.

**Two gaps to note.**

A `year_range` rule cannot be evaluated today. The `year` column on
`ce_user_garage` **already exists** — `dl-interest-profile.php` reads
it — but nothing in the app ever writes it: the add-vehicle handlers in
`garage.php` leave it out of their insert arrays, even though the DVLA
lookup returns `year_of_manufacture` and discards it. So the column is
empty and "Classics" matches nothing until that is fixed. No migration
needed, just one line in two insert arrays, and it stays **optional** on
the vehicle form.

There is also no `body_type`, `fuel` or engine-size column, so no rule
can match on those. That rules out a clean "EV" or "hot hatch" group —
the first can only see EV-only makes (Tesla, Polestar), and the second
has to fall back on keyword matching against free text. Those rule types
are deliberately **not offered**, because a rule naming a column that
does not exist would match nothing forever, which is worse than not
having it.

### 3.3 `ce_group_members` — who is in

```sql
CREATE TABLE IF NOT EXISTS ce_group_members (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_id   BIGINT UNSIGNED NOT NULL,

  -- Network-wide: wp_users is shared across the multisite, so this
  -- needs no qualifier to be meaningful on any blog.
  user_id    BIGINT UNSIGNED NOT NULL,

  -- member | moderator
  role       VARCHAR(16) NOT NULL DEFAULT 'member',

  -- auto | joined.
  --
  -- 'auto' is "we put them here because of a car in their garage",
  -- 'joined' is "they tapped Join". The distinction decides what
  -- happens when they sell the car: an auto membership can lapse, a
  -- deliberate one must not.
  source     VARCHAR(16) NOT NULL DEFAULT 'auto',

  -- active | left.
  --
  -- NOT a deleted row, and this is the important one. If leaving an
  -- auto-populated group deletes the row, the next refresh sees the
  -- matching car and adds them straight back — the user can never get
  -- out, and will report it as a bug. 'left' is a tombstone the
  -- refresh is required to respect.
  status     VARCHAR(16) NOT NULL DEFAULT 'active',

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
               ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (id),

  -- One membership per person per group, whatever races.
  UNIQUE KEY uniq_member (group_id, user_id),

  -- The members list, and the count behind member_count.
  KEY by_group (group_id, status),

  -- "Which groups am I in" — every load of the groups page.
  KEY by_user (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 3.4 `ce_group_vehicles` — garages associated with groups

This is the piece asked for directly: a group's garage section, and
the route by which owning a car puts you in a group.

```sql
CREATE TABLE IF NOT EXISTS ce_group_vehicles (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_id   BIGINT UNSIGNED NOT NULL,

  -- ce_user_garage.id
  garage_id  BIGINT UNSIGNED NOT NULL,

  -- Denormalised from the garage row so "my vehicles in this group"
  -- and the permission check on hiding one need no join.
  user_id    BIGINT UNSIGNED NOT NULL,

  -- auto | manual, as above.
  source     VARCHAR(16) NOT NULL DEFAULT 'auto',

  -- active | hidden. 'hidden' is the owner saying "not this car in
  -- this group" — the per-vehicle version of the opt-out, which was
  -- named as a thing to support later. Costs nothing to allow for now
  -- and cannot be retrofitted onto deleted rows.
  status     VARCHAR(16) NOT NULL DEFAULT 'active',

  -- Which rule matched. Makes the association explain itself: "here
  -- because its make is Mazda" rather than an unexplained row.
  -- NULL for manual additions.
  rule_id    BIGINT UNSIGNED NULL,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (id),
  UNIQUE KEY uniq_group_vehicle (group_id, garage_id),

  -- The group's garage grid.
  KEY by_group (group_id, status),

  -- "Which groups is this car in", for the vehicle page and for
  -- cleanup when it is deleted.
  KEY by_garage (garage_id, status),
  KEY by_user (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

A user is a member of many groups and each of their vehicles sits in
many groups — nothing here is exclusive, which matches "single vehicle
will be part of many".

### 3.5 `ce_group_activity` — the feed index

Where "we generate the activity" lives, and the table that makes this
design worth the trouble.

**It is an index, not a store.** The content stays where it already
lives: a post stays in `ce_social_posts`, a vehicle in
`ce_user_garage`. A row here says only *this item belongs in this
group, and this is when it happened*. So it can be dropped and rebuilt
at any time, and nothing is lost when we change our minds about what
belongs in a feed.

```sql
CREATE TABLE IF NOT EXISTS ce_group_activity (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_id    BIGINT UNSIGNED NOT NULL,

  -- post | spot | vehicle | event | news
  item_type   VARCHAR(24)  NOT NULL,

  -- The id in that item's own table. No blog_id needed: every source
  -- table it points at is already network-wide.
  item_id     BIGINT UNSIGNED NOT NULL,

  -- Whose it is, for attribution and for blocking.
  user_id     BIGINT UNSIGNED NOT NULL DEFAULT 0,

  -- auto | member | curated.
  --
  -- 'member' is somebody posting into the group, 'auto' is us putting
  -- a matching spot or vehicle in front of them, 'curated' is an
  -- editorial pick. The feed can be filtered on this, and the app can
  -- say "posted in JDM" versus "matched your group".
  source      VARCHAR(16)  NOT NULL DEFAULT 'auto',

  -- Pinned items first, then date. One integer beats a separate
  -- pinned table and a separate weight table.
  weight      INT          NOT NULL DEFAULT 0,

  -- The item's own timestamp, copied in. The feed sorts on this, and
  -- the sources disagree about what their date column is called
  -- (post_date, created_at) — resolving that once at write time is
  -- what keeps the feed one indexed query instead of a five-way union.
  happened_at DATETIME     NOT NULL,

  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (id),

  -- An item appears in a group once. This is what makes the refresh
  -- idempotent: it can re-insert freely and the database discards the
  -- duplicates, so a run that half-finished is safe to repeat.
  UNIQUE KEY uniq_item (group_id, item_type, item_id),

  -- THE FEED QUERY. Everything the group page does, in one index.
  KEY by_group (group_id, weight, happened_at),

  -- For cleanup when an item is deleted anywhere in the system.
  KEY by_item (item_type, item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 3.6 One column elsewhere

A member posting *into* a group needs that recorded on the post
itself, not only in the index — the index is a cache, and "which group
was this posted in" is an authoritative fact the post detail screen and
the permission check both need.

```sql
ALTER TABLE ce_social_posts
  ADD COLUMN group_id BIGINT UNSIGNED NULL AFTER club_id;

CREATE INDEX idx_posts_group ON ce_social_posts (group_id, post_date);
```

A separate column from `club_id`, not a reuse of it. `club_id` holds a
WordPress post id and `group_id` holds a `ce_groups` id; they are
different id spaces and the same number means different things in
each. Overloading one column would make "is this a club post or a
group post" unanswerable — the same mistake `sql/spotted-posts.sql`
argues against at length, from the other direction.

---

## 4. How a group fills up

### The match, in one query

"Which groups does this vehicle belong to?" — the question behind
auto-population:

```sql
SELECT DISTINCT r.group_id, r.id AS rule_id
  FROM ce_group_rules r
  JOIN ce_groups g ON g.id = r.group_id AND g.status = 'published'
 WHERE r.is_active = 1
   AND (
         (r.rule_type = 'make'  AND r.value = LOWER(TRIM(?)))
      OR (r.rule_type = 'model' AND r.value = LOWER(TRIM(?)))
       );
```

Two indexed lookups, so it can run inline when a vehicle is added or
edited rather than waiting for a cron.

**Decided: it suggests, it does not join.** A match puts a row in
`ce_group_vehicles` and powers the "Based on your garage" section;
`ce_group_members` is written only when somebody taps Join. So adding a
Golf proposes the VW and Golf groups and joins nothing — the user
decides.

The `source` column still records `auto` versus `joined`, because that
distinction has to be storable before auto-join could ever be switched
on, and because it is what decides whether a membership may lapse when
the car is sold.

### The refresh, for everything else

Spots, posts and events need sweeping rather than hooking, because they
arrive in bulk and because the rules change under them. That is
exactly the job `dl-groups-refresh.php` already does for gallery
cards, and the new script should be a copy of its shape rather than a
new invention:

- standalone PHP, runnable from the shell or pinged over HTTP with a key
- **incremental by default** — only items touched since the last
  successful run, so the normal cost is proportional to new activity
- `--full` to rebuild from nothing, which is the whole point of an
  index
- safe to run twice, which `uniq_item` guarantees

What a pass does:

1. new garage vehicles → match → `ce_group_vehicles` (not memberships)
2. new spots → match `spotted_vehicle` against the rules → `activity`
3. new posts with a `group_id` → `activity` as `source = 'member'`
4. events whose club or tags match → `activity`
5. recount the three cached counters on `ce_groups`

Note step 2: matching spots is the one that needs the AI-derived
vehicle data mentioned earlier, because `spotted_vehicle` is free text.
`sql/spotted-posts.sql` already anticipated this — *"if it later needs
matching to makes and models, this column is what gets normalised"*.
A `spotted_make` / `spotted_model` pair written at post time, or
backfilled, is what turns a spot into a group match. Out of scope here,
but this is the hook it attaches to.

---

## 5. How this reaches users globally

### It already does

Worth stating plainly, because it is the whole reason for the design:
**there is no mechanism needed for the global part.** None of the five
tables has a `blog_id`, `wp_users` is network-shared, and every table
they reference is network-wide too. A group created once is visible to
every user of every blog, immediately, with nothing to copy or
synchronise and no `switch_to_blog` anywhere in the read path.

The regional clubs are untouched by all of this. They stay as
WordPress `clubs` posts on their own blogs, so each carevents site
keeps showing exactly its own clubs and nothing new appears in it.
That was the constraint, and custom tables satisfy it by not
participating in the blog system at all.

### Two id spaces, one list

**Decided: bare ids, with a `type` field alongside.**

A club is a WordPress post id and a group is a `ce_groups` id, and both
are small integers — so group 42 and club 42 both exist and mean
different things. Rather than prefixing the id, every summary carries
what it is:

```json
{ "ID": 42, "type": "group", "kind": "scene", "slug": "jdm" }
{ "ID": 42, "type": "club",  "is_national": true }
```

Which keeps existing club responses working unchanged — `type` is
additive, and anything that does not send it is a club.

The one place this needs care is **links**, where a bare number travels
with no `type` beside it: a deep link, a share URL or an SEO page. Those
use the slug instead, which is why `ce_groups.slug` exists:

```
/groups/jdm          a global group
/clubs/1234          a club
```

Different paths, so there is nothing to disambiguate. The app passes
bare numeric ids internally; only URLs use slugs.

### Global groups have no geography

Also decided: a global group is **national-and-above by definition**.
No lat, no lng, no radius, no `location_type`. Local is what regional
clubs are for, and they keep that to themselves.

This is why global groups do not belong in `dl_get_clubs()` — that
function is almost entirely a geographic query, and a group with
members in four countries has no distance from anybody.

### The endpoints

A **new** endpoint rather than another branch inside `dl_get_clubs`:

```
GET  /app/v2/groups?kind=scene&limit=12
GET  /app/v2/groups/{slug}
GET  /app/v2/groups/{slug}/activity?page=1
GET  /app/v2/groups/{slug}/vehicles?page=1
GET  /app/v2/groups/{slug}/members?page=1
POST /app/v2/groups/{slug}/join
POST /app/v2/groups/{slug}/leave
```

`dl_get_clubs` is 350 lines of bounding boxes, radius filters,
`HAVING distance`, national-vs-local modes and a `switch_to_blog` —
all of it about geography. Global groups have no geography. Threading
them through that function means a second mode that ignores most of it,
and it would inherit the bug noted below. A separate handler reading
five clean tables is smaller than the branch would be.

The list response should match `format_club_for_api()` field for field
(`ID`, `title`, `cover_image`, `logo`, `member_count`, `role`,
`is_member`, …) so the app's existing parse works unchanged, plus:

```json
{
  "type": "group",
  "kind": "scene",
  "slug": "jdm",
  "strapline": "Japanese performance, old and new",
  "is_member": true,
  "member_source": "auto",
  "my_vehicle_count": 1
}
```

`member_source` is what lets the tile say "You're in this because of
your MX-5" instead of an unexplained Joined state.

### Mapping onto the screen as built

`groups_screen.dart` needs no restructuring — it was built with this
swap in mind:

| Section | Today | Becomes |
| --- | --- | --- |
| Scene groups | `_mockSceneGroups` | `GET /groups?kind=scene` |
| Marque & model | `_mockMarqueGroups` | `GET /groups?kind=marque` |
| Based on your garage | `_loadGarageMatches()`, derived in the app from the garage | `GET /groups?mine=garage` — the server already knows, via `ce_group_vehicles` |
| Your groups | `ClubApiService.getMyClubs()` | unchanged, plus joined global groups |
| All groups | `ClubApiService.fetchClubs()` | unchanged |

`_loadKind()` is the single swap point for the first two. The third is
the interesting one: the app currently reads the garage and guesses at
matches client-side, and once `ce_group_vehicles` exists the server can
answer it properly, with member counts and images the app cannot
derive.

### The SEO site

`/guess/<date>` established the pattern and groups fit it:
`/groups/<slug>` renders from `GET /app/v2/groups/{slug}` plus the
activity feed, no auth, app-matching styling, with joining and posting
only in the app. Because these groups are global, one page serves every
region — no per-region routing, unlike clubs.

---

## 6. What this costs

Honestly, three things:

**No ACF, so an admin screen has to be built.** This is the real
trade. A club post gets the WordPress editor, media library and ACF
fields for free; `ce_groups` gets none of that. For a few dozen
curated groups the practical answer is to seed them with SQL and build
a small network-admin list screen — kind, title, slug, images, status,
featured, and the rule rows — when editing by hand becomes annoying.
Worth being clear that "admin ACF field" is not available in this
design, because that was the earlier assumption.

**Two groups systems, for a while.** Clubs stay as posts and groups
are rows, and the groups page shows both. Every mixed list has to carry
the `type` field, and any screen that forgets it will eventually open
the wrong thing. If user clubs ever migrate into `ce_groups` that
collapses back to one system, and the schema allows it — but that is a
much larger job and not proposed here.

**Counters can drift.** `member_count` and friends are caches. The
refresh recomputes them, and the same reconciliation idea as
`dl_points_reconcile()` applies: a query that finds rows where the
cache and the count disagree.

---

## 7. Found along the way: `dl_get_clubs` is broken for US users

Not part of this design, but it needs fixing either way, and it would
have been inherited by anything built inside that function.

`dl_get_clubs()` picks a blog from the user's country:

```php
switch_to_blog(dl_normalise_site($country) === 'US' ? DL_BLOG_US : DL_BLOG_UK);
```

But every club in existence is created on the UK blog —
`dl_create_club_initial()` and `ce_update_club_data()` both
`switch_to_blog(dl_default_blog_id())`, and `dl_get_my_clubs` and
`dl_get_club_details` switch there to read. So a user in North America
browsing groups queries a blog with no clubs on it, and **sees an
empty list**, while "Your groups" works fine because it reads the UK
blog.

`dl_get_featured_clubs()` has the same line and partly covers for it
with `dl_worldwide_club_ids()`.

Worth confirming against live before acting — but if it is as it reads,
it is a bigger and much cheaper win than anything in this document.

Also worth noting: `club_location_type = 3` already means **worldwide**,
with a comment explaining it had to be a value nothing used. That is a
precedent for the global idea inside the club model — but it is still
per-blog, so a worldwide club on the UK blog is invisible to a query
against the US blog. It does not solve the problem; it shows the
problem was already noticed.

---

## 8. Decisions — settled

1. **Posts are global.** A post has no country and anyone can view it.
   Nothing to build: `ce_social_posts` already has no `blog_id`, so this
   is the behaviour today. A post in a global group reaches everybody.

2. **Bare ids, with a `type` field** to say group or club, and slugs on
   URLs where no `type` travels alongside. See §5.

3. **Suggest, do not auto-join.** Matching fills `ce_group_vehicles`
   and the "Based on your garage" section; membership needs a tap.

4. **The garage `year` is optional.** The column already exists, so
   there is no migration — `garage.php` just needs to start storing the
   DVLA year it already fetches, and the field stays optional on the
   form. Until then, `year_range` rules match nothing, visibly.

5. **Global groups are national-and-above**, with no geography at all.

### Still open

- **The group vocabulary.** The seed file's makes and models are
  guesses at how users have spelled things in free text. The tool's
  uncovered-makes panel is what corrects them against reality, and the
  seed file should be expected to need one editing pass after the first
  preview.
- **Do dream cars count?** `primary_car = '2'` is a dream car, and the
  matcher currently includes them — so somebody who wants a 911 appears
  in the Porsche group alongside somebody who has one. Defensible either
  way; easy to change.
- **Spot matching** needs `spotted_vehicle` normalised into a make and
  model before it can be exact. See `spots-backend-notes.md`.

---

## 9. Build order

Nothing in the existing API changes until the first step has been looked
at and approved.

1. **Standalone fileset — built.** `sql/global-groups.sql`,
   `tools/dl-global-groups.php`, `tools/global-groups-seed.php`. Creates
   the tables, seeds the groups, and shows what each one matches against
   live data. Touches no existing endpoint.
2. **Fix the group vocabulary** from what that page reports.
3. **The refresh pass — built.** `dl-global-groups-refresh.php`, modelled
   on `dl-groups-refresh.php`: incremental by default, `--full` to
   rebuild, `--dry` to report. Populates `ce_group_vehicles` and
   `ce_group_activity`, and writes no memberships. The rule matcher it
   shares with the admin page lives in `tools/global-groups-match.php`,
   so the preview cannot promise rows the refresh would not write.
4. **The read endpoints** — `/app/v2/groups*`, new handlers, no change
   to `dl_get_clubs()`.
5. **The app** — swap `_loadKind()` and the garage-matches list off
   their placeholder arrays.
6. **Join, and posting into a group** — the point at which
   `ce_group_members` and `ce_social_posts.group_id` start being written.
