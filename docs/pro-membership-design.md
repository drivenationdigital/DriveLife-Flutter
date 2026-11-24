# Pro membership: the table, and what it can honestly hold

Design note. **Nothing here is built** — no SQL has been run, no
endpoints exist. This is the shape to agree before any of that.

---

## 1. The benefits, and what they do NOT do

Decided:

- a badge on your profile
- early access to events
- a range of partner discounts and benefits

**Every one of these ADDS. None of them takes anything away.** Nothing
a free account can do today stops working when this ships. No cap
arrives on routes, on photographs or on vehicles. Somebody who never
pays loses nothing they already had.

That is worth stating plainly, because it makes the earlier
grandfathering decision moot: there is nothing to grandfather. No
existing user wakes up unable to add what they could add yesterday, and
there is no angry cohort to manage. It is the safest shape a first
paywall can have.

`lib/models/pro_limits.dart` holds the keep-what-you-have rule
anyway, tested, and is deliberately **unused**. It is there for the day
a capped benefit is added, so the rule is settled before it is needed
rather than during an argument about it.

### What each one needs

| benefit | what already exists | what is missing |
|---|---|---|
| profile badge | nothing | a flag the profile reads, and the badge |
| early access to events | the events and ticketing system | a per-event "members from / public from" pair, and a gate on the ticket |
| partner discounts | `endpoints/offers.php`, `offers_api_service.dart` - offers list, redeem, redemption history | a members-only marking on an offer, and a check on redeem |

**Partner discounts is the closest to done.** Offers already exist, are
listed, and can be redeemed with the redemption recorded. What is
missing is one flag saying "this one is for members" and a check in the
redeem path. That makes it the sensible first benefit to actually wire.

**Early access is the one with a real design question in it.** It means
an event has TWO on-sale times rather than one, and every surface that
lists or sells a ticket has to know which it is looking at - the
events list, the detail page, the checkout, and whatever sends the
"tickets are live" notification. Worth scoping on its own before it is
promised in a store listing.

**The badge is the cheapest and the most visible.** It is also the one
that makes the other two credible: a member who sees nothing different
about their own profile has no daily evidence they are a member.

## 2. The hard part, before the schema

**The store decides whether somebody is subscribed. This table only
records it.**

That has to be settled first, because it decides what every column
means. A subscription can change without the app being opened:

- it renews each month or year, by itself
- the card fails, and it enters a grace period, then lapses
- it is cancelled in iOS Settings or the Play Store, not in our app
- it is refunded, which revokes it immediately
- Apple and Google can both change it for support reasons

None of that goes through us. So `pro_users` is a **mirror** that is
only as fresh as the last thing that updated it, and the two things
that keep it fresh are:

1. **Server-to-server notifications** — App Store Server Notifications
   V2 and Google Play Real-time Developer Notifications. Both POST to a
   URL we own whenever a subscription changes. This is the real source.
2. **Receipt validation on purchase and restore** — what the app sends
   when somebody buys, which the server verifies with the store.

Without (1), somebody who cancels stays Pro in our table forever.

**The app must never decide its own Pro status from a local flag.** A
rooted device lies, and the only answer that matters is the one the
server holds.

---

## 3. What you asked to store, and whether it can be

| you asked for | can we | notes |
|---|---|---|
| when they joined | **yes** | first purchase, from the receipt |
| how much they paid | **partly** | see below |
| if they cancelled | **yes** | from the store notification |
| the reason for cancelling | **only if they tell us** | see below |
| a membership review | **yes** | it is ours, we just ask |

### "How much they paid"

The purchase itself does not hand the app a price it can be trusted
with. What you get reliably is the **product** and the **currency and
amount in the store's own records**, read back from Apple's and
Google's server APIs.

So: store the product id and the currency and amount **as the store
reported them at that renewal**, not as the app displayed them. They
drift — prices change, tiers change, a Dublin subscriber pays euros,
and tax is handled differently in each country. A single "paid" column
on the user will be wrong within a year.

That is why §4 has a separate `pro_events` table. One row per renewal
is the only version of "how much have they paid us" that stays true.

### "The reason for cancelling"

**Neither store will tell you.** They do not ask, and they do not pass
one on.

Worse, the usual cancel path never touches our app at all: somebody
opens iOS Settings, taps Cancel Subscription, and the first we hear is
a notification saying it lapsed. There is no moment to ask them.

So the field is worth having, but be clear about what it is: a
**voluntary exit survey**, answerable only by the minority who happen
to open the app after cancelling. Expect it to be mostly null, and do
not build a dashboard that treats the answers as representative.

The one way to improve the odds is to notice the lapse on next open and
ask once, gently, with a skip — not a modal they must answer.

---

## 4. The shape

Two tables, not one. The split matters: a **membership** is a current
state, a **payment** is a historical fact, and squeezing both into one
row means either overwriting history or never knowing what is true now.

### `ce_pro_members` — one row per user, the current state

| column | type | notes |
|---|---|---|
| `user_id` | BIGINT, unique | the member |
| `status` | VARCHAR(16) | `active`, `grace`, `lapsed`, `refunded` |
| `platform` | VARCHAR(8) | `ios` / `android` — where they bought |
| `product_id` | VARCHAR(64) | monthly or yearly, as currently held |
| `store_ref` | VARCHAR(128) | Apple `originalTransactionId` / Play `purchaseToken`. **The join key to the store, and the one that must be unique** |
| `joined_at` | DATETIME | first ever purchase. Never overwritten on renewal |
| `current_period_end` | DATETIME | when it next renews or lapses |
| `cancelled_at` | DATETIME NULL | when they turned off renewal — **not** when access ends |
| `cancel_reason` | VARCHAR(255) NULL | only if they tell us. See above |
| `environment` | VARCHAR(8) | `sandbox` / `production`. **Keep these apart or a tester is a paying member** |
| `updated_at` | DATETIME | last time a store notification touched this |

### `ce_pro_events` — one row per thing that happened

| column | type | notes |
|---|---|---|
| `id` | BIGINT | |
| `user_id` | BIGINT | |
| `kind` | VARCHAR(24) | `purchase`, `renewal`, `cancel`, `lapse`, `refund`, `grace`, `resubscribe` |
| `product_id` | VARCHAR(64) | what it was for |
| `amount_minor` | INT NULL | 499, not 4.99. Money in a float is money lost |
| `currency` | CHAR(3) NULL | GBP, EUR, USD |
| `store_ref` | VARCHAR(128) | ties it to the membership |
| `store_event_id` | VARCHAR(128), unique | **the idempotency key** |
| `occurred_at` | DATETIME | when the store says it happened |
| `raw` | TEXT NULL | the notification as received, for when the above disagrees with reality |

**`store_event_id` unique is not optional.** Both stores retry
notifications they think failed, so the same renewal arrives two or
three times. Without that constraint every retry is another renewal in
your revenue figures.

### `ce_pro_reviews` — or a column, if it is only ever one

If the membership review is a one-off rating and a sentence, it can be
two columns on `ce_pro_members`. If you want to ask again after six
months, or ask separately about the app and the membership, it is its
own table with `user_id`, `kind`, `rating`, `comment`, `created_at`.

Worth deciding now, because moving a column into a table later means a
migration on live data.

---

## 5. Three things that bite

**Money as integers.** `amount_minor INT` holding 499. A float holding
4.99 is a different number than you think it is, and summing a year of
them does not give the figure the bank has.

**Sandbox and production in the same table.** A sandbox subscription
renews every few minutes and would otherwise fill the events table and
turn every tester into a paying member in your numbers. The
`environment` column exists for that, and every query that counts
members has to filter on it.

**The user id is not the store's identity.** Apple's
`originalTransactionId` and Play's `purchaseToken` belong to an *Apple
ID or Google account*, not to a DriveLife account. One person can sign
into DriveLife on a phone whose App Store account is someone else's —
that is the usual family-sharing arrangement. So `store_ref` unique is
right, and the link from it to `user_id` is "who redeemed it", which
can change. Decide what happens when it does.

---

## 6. What still needs deciding

1. Which benefit is wired first. Partner discounts is the shortest path; the badge is the most visible.
2. Whether the review is columns or a table (§4).
3. What happens when a `store_ref` is redeemed by a second account.
4. What a LAPSED member keeps. Nothing is capped, so their routes
   and photographs are not in question — but the badge, the early
   access and the partner offers all have to switch off, and the
   badge is the one people will notice disappearing.

---

## 7. Order of work, when the API is open again

1. `ce_pro_members` and `ce_pro_events`, additive, nothing existing
   touched.
2. Receipt validation endpoint — the app sends a purchase, the server
   verifies with the store and writes the row.
3. Store notification webhooks, one per platform. Idempotent on
   `store_event_id`.
4. A `pro` flag on the existing user payload, read from the table, so
   the app has an answer without a second request.
5. Gating, using `ProLimits`, which already exists and is tested.

Nothing in 1 to 4 has been started.
