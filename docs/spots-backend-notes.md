# Spots — backend notes

The home page now has a "Log a spot" tile and a **Recent spots**
section (`lib/widgets/home/your_week.dart`). The tile works. The list
is empty and hides itself, because nothing can answer it yet.

---

## 1. Spots are write-only

`create-post.php` writes `spotted_vehicle` on the post, and **nothing
reads it back**. No feed selects the column, so there is no way to ask
"what has been spotted recently".

A grep across `php-api/` finds `spotted_vehicle` in exactly two places:
`endpoints/create-post.php` and `sql/spotted-posts.sql`.

So the empty section is not a placeholder — it is the truth. It will
start showing rows the moment a feed exists, with no UI change.

### Suggested endpoint

```
GET /app/v2/spots?limit=3
→ { success: true,
    spots: [ { post_id, spotted_vehicle, image,
                user: { id, name, avatar },
                rarity: "legendary" } ] }
```

Mapped in the app by `RecentSpot`. The row needs four things: the
vehicle, who spotted it, a thumbnail, and the rarity badge.

Open questions:

- **Recent by whom?** Everybody's spots, people they follow, or spots
  near them? The design says "RECENT SPOTS" with no qualifier, which
  suggests everybody — but a global feed on the home page of a growing
  app eventually shows the same three cars to everyone.
- `spotted_vehicle` is free text from an autocomplete over a curated
  list (`lib/data/vehicle_suggestions.dart`), so it is usually but not
  always a clean "Porsche Carrera GT". Worth deciding whether the feed
  trusts it or normalises it.
- The design shows a first name and an initial ("Mark R.", "Seb K.").
  Is that a formatting rule for the app to apply, or does the endpoint
  send a display name?

## 2. Rarity / status — TO DO TODAY

**This is the piece explicitly deferred.** Spots are to carry a status
we set — the design shows `LEGENDARY` and `EPIC` badges.

Nothing stores one. `RecentSpot.rarity` is nullable and the badge is
simply not drawn when it is absent, so the list works without it and
gains the badges when they arrive.

To decide:

- **The values.** Legendary and Epic are the two in the design. What
  is the full ladder, and is there a bottom rung that means "ordinary"
  and shows no badge at all?
- **Who sets it.** "statuses that we can set" reads as manual, by an
  admin, per spot. If so it wants the same kind of admin field as the
  group `kind` — and a queue, because somebody has to go and look at
  them.
- **Or is it derived?** Rarity could come from the vehicle rather than
  the spot — a Carrera GT is legendary whoever photographs it — which
  would make it a property of the curated vehicle list, set once per
  model instead of once per sighting. That is far less work to run and
  probably what people would expect, but it cannot reward somebody for
  a particularly good catch of an ordinary car.
- **Does it pay points?** Spots already award 300 (`spot_added` in
  `dl_points_rules`). If a legendary spot should pay more, the award
  cannot happen at post time — the status is not known yet — so it
  would need a second, later award keyed to the same ledger subject.

The badge widget takes the status **by name** and styles anything that
is not `LEGENDARY` as gold, so adding a value server-side does not
require an app release to display it.

---

## Smaller notes

- The home tile row is the game and the spot invitation side by side.
  On a day with no game scheduled the invitation takes the full width,
  rather than leaving a gap.
- Tapping a spot row opens `AppRoutes.postDetail` with the post id — a
  spot is a post, so there is no separate screen to build.
