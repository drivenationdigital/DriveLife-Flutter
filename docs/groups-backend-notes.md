# Groups — backend notes

Written while rebuilding the groups list page
(`lib/screens/clubs/groups_screen.dart`) from the supplied designs.
Nothing below is built yet; this records the agreed shape and the
questions still open, so the app and the server end up meeting.

> **Superseded in part.** This document assumes scene and marque groups
> are WordPress clubs carrying an ACF `kind` field. They are not — they
> became global objects in custom tables, because their activity is
> mainly generated at our end and because a CPT cannot be global. See
> `global-groups-design.md`. What stays true here: the three kinds, the
> app-side `GroupKind` mapping, the decision to drop filters, and the
> gaps listed under "Still missing". What does not: the ACF field and
> the suggestion to extend `/app/v1/clubs` with a `kind` filter.

Two sections are live. The rest draw from placeholder lists at the top
of that file.

| Section | Source today |
| --- | --- |
| Search groups | **Live** — `GET /app/v1/clubs?filters={"search":…}` |
| Your groups | **Live** — `GET /app/v1/clubs/my-clubs` |
| Based on your garage | Placeholder |
| Scene groups | Placeholder |
| Marque & model | Placeholder |

---

## The model

A group gets an admin-set field saying what kind it is:

| kind | What it is | Who makes it |
| --- | --- | --- |
| `scene` | Broad, by interest rather than by car — JDM, Classics, Track Days, Detailing | DriveLife |
| `marque` | One make or one model — Land Rover Defender, Mazda MX-5 | DriveLife |
| `club` | Everything a member made themselves | Users |

Mirrored in the app as `GroupKind` in `groups_screen.dart`.

**National vs local is not part of this field.** It is already stored —
`is_national` on the club summary, `location_type` on `MyClub` — and
recording one fact in two places is two places for it to disagree. A
user club is `kind: club` *and* national or local; the two are
independent.

**One field, not three endpoints.** Every section on this page is the
same query with a different `kind`, which is why the app has a single
`_loadKind()` to swap over rather than three.

### Suggested API

Extend the existing list endpoint rather than adding new ones — it
already has pagination, search, member counts and the membership flags:

```
GET /app/v1/clubs?filters={"kind":"scene"}
GET /app/v1/clubs?filters={"kind":"marque","limit":3}
```

`kind` should also come back on every club summary, so the app can tell
a scene from a user club in a mixed list such as search results.

Defaulting matters: existing clubs have no value for this field, and
they are all user clubs. Whatever reads it should treat absent as
`club`, not as "unclassified", or every club made before the field
existed disappears from the one section it belongs in.

---

## Still missing, beyond the `kind` field

### 1. A vehicle has no relationship to a group

Blocks **Based on your garage**. The garage knows make, model, year and
registration; a group has a title and a category, and the two never
meet.

With `kind: marque` existing, the obvious route is to give a marque
group the make and model it represents, and match on that. Which raises:

- Does a marque group store `make` + `model`, or just `make` for
  make-wide ones ("EV Owners" is neither)?
- Match on the user's current vehicles only, or past ones too? Dream
  cars?
- Filter out groups already joined? The design implies yes — every row
  has a Join button.

Worth returning *why* a group was suggested (`matched_on: "Polestar 2"`),
which is the difference between a recommendation and a guess. The app
has nowhere to show it yet, but it is much easier to add to a response
than to retrofit.

### 2. Join, from a list

The Join button in that card has nowhere to go. `POST /app/v1/club-join`
exists but takes `questions` — it is built for groups that vet
applicants, and the Dart client (`submitJoinRequest`) requires the
answers.

Needed:

- A path for a group with no questions, so one tap joins.
- `join_policy: "open" | "questions" | "invite"` on the summary, so the
  list knows which it is **before** the tap. A button that sometimes
  joins and sometimes opens a form is worse than two different buttons.
- The new `member_count` in the response, so the row can update without
  re-fetching the list to move a number by one.

Scenes and marques are presumably always `open`; a user club is the one
that might ask questions.

Until this exists the Join button only toggles its own label, locally.
It sends nothing.

### 3. No member avatars on a summary

The scene tiles in the design show two overlapping member faces. No
endpoint returns them, so the tiles render without and look flatter
than the mock. Something like `recent_members: [{id, avatar}]`, capped
at two or three, on the list response.

---

## Decided: no filters on this page

The old screen had club-type, location and a Google Places input. They
are gone from the new one and are not coming back here — filtering
moves into Club search later.

---

## Smaller notes

- **Member counts are abbreviated** above a thousand ("3.2k members")
  to match the design. The API should keep sending the integer; the
  formatting is the app's business.
- **`cover_image` is sometimes a WordPress upload and sometimes a
  Cloudflare URL.** Both render, but the WordPress ones are full-size
  originals being downloaded into a 268px card.
- **Placeholder rows are inert.** Tapping one shows a snackbar saying
  so, rather than failing silently, so it is obvious during testing
  which parts are not wired up.
- **Empty sections hide themselves**, heading included — so as each
  `kind` starts returning real rows, its section appears on its own.
