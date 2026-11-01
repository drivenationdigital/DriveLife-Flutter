# User interest signals

A catalogue of everything a user already does in DriveLife that says
something about what they are interested in, where that data lives
today, and what it would take to turn it into a usable interest
profile.

**Nothing here is built.** This is a survey and a proposal, written so
the decisions can be made before any of it is coded.

The point of an interest profile is to answer questions the app cannot
answer now:

- which groups to suggest on the groups page ("Based on your garage"
  is the first consumer, and it currently has nothing to work with)
- which events to put in front of somebody
- which posts belong in a personalised feed
- which notifications are worth sending

---

## 1. The signals that exist today

Ordered by how much they actually tell you, not by how easy they are
to collect. "Strength" is how confidently a signal predicts interest:
a car somebody owns is near-certain, a post they scrolled past is
nearly noise.

### Declared — the user has told us outright

| Signal | Where it lives | Strength | Notes |
| --- | --- | --- | --- |
| Vehicles in the garage | `ce_user_garage` | **Highest** | make, model, year, colour, mods. Current / past / dream are three different statements — `primary_car == '2'` is a dream car. |
| Dream cars specifically | `ce_user_garage` | **Highest** | Aspiration, not ownership. Capped at 5, so each one was a deliberate choice. |
| Signup interests | user meta (step 3 of signup) | High | The explicit list — 4x4 & Offroad, Trucks & Pickups, etc. Chosen once, never revisited, so it ages. |
| Vehicle modifications | `ce_user_garage_mods` | High | Says *how* they are into a car, not just which. |
| Groups joined | ACF `club_members` on the club | High | Joining is a deliberate, public act. |
| Events saved | user meta `favourite_events` | High | An intention to attend. |

### Behavioural — inferred from what they do

| Signal | Where it lives | Strength | Notes |
| --- | --- | --- | --- |
| Liking a vehicle | `ce_garage_likes` | High | The clearest "I like *this kind of car*" in the app — the liked vehicle has a make and model attached. |
| Tagging a vehicle in a post | `ce_social_posts_tags` (`entity_type = 'car'`) | High | Tagging is effort. |
| Tagging in a gallery | `ce_gallery_tags`, `ce_tagged_registrations` | High | Same. |
| Logging a spot | `ce_social_posts.spotted_vehicle` | High | They stopped and photographed it. Free text from a curated list. |
| Adding to a gallery | `ce_galleries`, `ce_gallery_links` | Medium-high | What they chose to collect. |
| Posting | `ce_social_posts` | Medium-high | Caption text, linked garage/event/club/venue. |
| Liking a post | `ce_social_posts_likes` | Medium | Cheap action; needs the post's subject to mean anything. |
| Liking a gallery photo | `ce_gallery_photo_likes` | Medium | As above. |
| Commenting | `ce_social_posts_comments` | Medium | Costlier than a like, so a stronger signal per unit. |
| Following a user | user meta `followers` / following | Medium | Interest in a person, which proxies for their cars. |
| Guess the car plays | `ce_guess_guesses` | Low-medium | Says they engage with the game, not much about cars. |
| Poll votes | `ce_post_poll_votes` | Low-medium | Depends entirely on the poll. |
| Points-earning actions | `ce_points_ledger` | — | See §3: a partial log of several of the above, **with timestamps**. |

### Not recorded at all

These happen constantly and leave no trace. They are the cheapest
signals individually and, in aggregate, some of the most useful —
and every day without logging is a day of them lost.

| Signal | Why it matters |
| --- | --- |
| Searches | Someone typing "Defender" repeatedly is the loudest possible statement of interest. Nothing logs a query. |
| Screens opened | Which vehicle, event, group or venue pages somebody actually looks at. |
| Dwell time | How long on a vehicle page separates a glance from a study. |
| Feed impressions | What was shown and *not* engaged with — the negative signal that stops a profile only ever growing. |
| Tab and filter use | Which home section, which event filters. |
| Notification opens | Which subjects pull somebody back into the app. |
| Spot composer abandons | Started logging a spot and gave up — still says they saw something. |
| QR scans | `ce_qr_code_to_profile` exists; whether scans are logged needs checking. |

---

## 2. What a signal needs to be useful

A row saying "user 12 liked garage 48" is not an interest. It becomes
one when it resolves to a **subject**: a make, a model, a category, a
region, an era.

So every logged action wants three things:

1. **Who** — user id.
2. **What they did** — a verb (`liked`, `tagged`, `joined`, `viewed`).
3. **What it was about** — resolved as far as possible at write time:
   `make=Porsche`, `model=911`, `category=JDM`, `region=Yorkshire`.

That third part is the hard one and the part worth getting right
first. Resolving at write time costs a lookup per action; resolving at
read time means every consumer re-implements "what make is garage
48?", and they will disagree.

Suggested shape — a thin log, with the interpretation stored beside
the raw fact:

```
ce_user_signals
  id, user_id,
  verb,                -- liked | tagged | joined | added | spotted | viewed | searched
  object_type,         -- garage | post | gallery | club | event | query
  object_id,
  subject_make,        -- resolved, nullable
  subject_model,       -- resolved, nullable
  subject_category,    -- resolved, nullable
  weight,              -- how much this verb is worth
  created_at
```

Keeping the raw `object_type`/`object_id` alongside the resolved
subject matters: when the resolution rules improve, the log can be
re-interpreted rather than being stuck with whatever was understood on
the day.

---

## 3. `ce_points_ledger` is already half of this

Worth knowing before anything new is built: the points ledger is
already an append-only, timestamped log of user actions.

```
user_id, rule, subject_key, balance_after, created_at
```

`rule` is the verb (`vehicle_added`, `post_added`, `gallery_added`,
`spot_added`, `guess_correct`) and `subject_key` is a stable
identifier for the thing it was about — for a vehicle, the normalised
registration.

It covers only actions that pay points, and the subject keys were
designed for deduplication rather than for analysis. But it is real,
it has dates, and it is the single best existing source for "what has
this user been doing and when".

**Decision to make:** extend the ledger with non-paying verbs, or keep
points and signals as separate concerns and write a new table. My
inclination is a new table — the ledger's uniqueness constraint
(one award per user/rule/subject) is exactly wrong for signals, where
the tenth time somebody likes a Porsche is the whole point.

---

## 4. Backfill: what can be recovered

The good news is that most of the strong signals are stored as
**state**, not as events — the row for "user 12 likes garage 48" is
still there. So the *fact* is recoverable even though the action was
never logged.

| Source | Backfillable? | Dates? |
| --- | --- | --- |
| Garage vehicles | Yes | Yes — rows carry dates |
| Garage likes | Yes | **Likely** — `ce_garage_likes` is written with `created_at` |
| Post likes | Yes | **No.** `ce_social_posts_likes` is `(post_id, user_id)` and nothing else. The post's own date is the only stand-in, which answers "likes on posts from this period", not "likes cast in this period". |
| Gallery photo likes | Yes | Needs checking against the live schema |
| Post / gallery tags | Yes | Via the parent post's date |
| Spots | Yes | Via the post's date |
| Group memberships | Yes | **No** — ACF field on the club post, no join date |
| Saved events | Yes | **No** — a user-meta array, no dates |
| Follows | Yes | **No** — user meta, no dates |
| Points ledger | Yes | Yes |
| Searches, views, impressions | **No** | Never recorded. Gone. |

Two practical conclusions:

- **A one-off backfill is worth doing** and will produce a usable
  profile for existing users on day one, rather than starting everyone
  cold.
- **Undated rows need a policy.** If recency weighting is part of the
  model, a backfilled follow with no date has to be given one — the
  parent object's date, or a flat "before the log existed" marker that
  the weighting treats as old. Pretending they all happened on
  migration day would make every long-standing user look like they
  joined everything this morning.

The schema checks above should be confirmed against the live database
before anyone plans around them — several of these tables predate the
app and were not designed for this.

---

## 5. Open questions

- **Recency.** Does an interest decay? Somebody who owned a Golf for
  five years and sold it last month is not a Golf owner now, but they
  are not nobody either.
- **Negative signals.** Is "shown it and ignored it repeatedly" worth
  recording? It is the only thing that stops a profile growing
  monotonically, and it is also the most invasive to collect.
- **Volume.** Every view and scroll is a lot of rows. Write them raw
  and aggregate nightly, or aggregate in the app and send summaries?
- **Visibility.** Does the user see their own profile? Can they
  correct it? A visible, editable profile is a feature; an invisible
  one that silently decides what they see is the thing people object
  to when they find out.
- **Privacy and consent.** Behavioural profiling has obligations under
  UK GDPR — a lawful basis, a retention period, and disclosure in the
  privacy policy. Worth settling before collection starts, because
  retrofitting consent to data already gathered is far harder than
  asking first.
- **Messages are out.** Chat content should not be a signal source at
  any strength. Mentioning it only to rule it out.
