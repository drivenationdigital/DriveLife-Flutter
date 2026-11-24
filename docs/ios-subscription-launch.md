# DriveLife memberships: iOS launch checklist

Where the subscription work stands, what is blocked, and what is left.
**iOS only.** Google Play is deliberately out of scope until this ships -
see the last section for what that costs.

Branch: `feature/subscriptions`. Last updated 24 November 2026.

---

## Done

### App Store Connect

- [x] **Subscription group created** - "DriveLife Plus"
- [x] **Three products created**, all currently *Prepare for Submission*

  | level | product id | duration |
  |---|---|---|
  | 1 | `drivelife_supercharged_yearly` | 1 year |
  | 2 | `drivelife_plus_monthly` | 1 month |
  | 2 | `drivelife_plus_yearly` | 1 year |

  Level 1 outranks level 2, so SuperCharged is an upgrade from either
  Plus plan, and monthly/yearly are a crossgrade of each other.

### Local testing

- [x] **`ios/DriveLife.storekit`** written, with the three products at
      matching ids and levels
- [x] **Wired into the shared Runner scheme**, so it is committed and
      applies to any checkout - no per-machine setup
- [x] **Purchase runs end to end in Xcode** - real StoreKit 2 APIs, no
      Apple account, no charge
- [x] **Found and documented the trap**: `flutter run` ignores the
      scheme's StoreKit configuration. It must be launched from Xcode,
      with `flutter attach` for hot reload. `flutter clean` and
      `pod install` can both silently drop the setting.

### The app

- [x] **`StoreSubscriptions`** is the real implementation and the
      default. `FakeSubscriptions` is reachable only by being handed in
      - the demo screen and tests - and throws if it is ever reached in
      a release build.
- [x] **One shared service**, owned by `MembershipSync`. The paywall
      borrows it rather than building a second, which would have had two
      listeners calling `completePurchase` on the same transaction.
- [x] **Entitlement read at launch.** Somebody who subscribed last month
      has bought nothing this session and is still a member, so the app
      asks the store on startup. Verified silent on both platforms: under
      StoreKit 2 `restorePurchases` reads local entitlements and does
      **not** call `AppStore.sync()`, so there is no password prompt.
- [x] **`MembershipProvider` keeps three sources apart** - demo override,
      server, store - in that precedence. The server slot is empty today
      and takes over the moment it is filled, with nothing else changing.
- [x] **Real expiry date** from `SK2PurchaseDetails.expirationDate`,
      rather than computing "today plus a month", which is wrong for
      everybody who did not subscribe in this session.
- [x] **Native manage/cancel sheet** (`showManageSubscriptions`), not a
      link to apps.apple.com. The link form cannot be exercised under a
      local StoreKit configuration, so the cancel path - the one a
      reviewer always checks - was untestable.
- [x] **Cancelled state handled.** `in_app_purchase` exposes no
      auto-renew flag on either platform, so this needed a native channel
      (`drivelife/subscription` in `AppDelegate.swift`) reading StoreKit
      2's `RenewalInfo`. Three states now: renewing, cancelled-but-still-
      entitled, and unknown. Unknown is a real third answer and draws
      cautious wording rather than guessing.
- [x] **Staleness closed in both directions** - re-reads after the manage
      sheet closes, and on app resume, because a cancellation can happen
      in iOS Settings with the screen open behind it.
- [x] **Paywall surfaces**: membership card on the profile, row in Edit
      profile, badges, upsell sheet.
- [x] **Remote config live** - `GET /app/v2/membership-config` is
      **deployed and returning 200**. Benefit copy, taglines and the ad
      switch all change without a build. Falls back server to cache to
      bundled, never blank.
- [x] **Ads** behind the membership gate and the remote switch, which
      defaults **off**, so a build shipped before launch shows none and
      so does a build that cannot reach the config.
- [x] **Demo screen** covering every state, including
      cancelled-but-active, which otherwise needs Xcode's Transaction
      Manager to reach.

### Server (written, **not deployed**)

- [x] `php-api/sql/memberships.sql` - `ce_memberships` and
      `ce_membership_events`
- [x] `php-api/endpoints/membership.php` - `/membership/me`, `/link`,
      `/cancel-reason`, `/review`
- [x] `php-api/endpoints/membership-apple.php` - App Store Server API
      client and the V2 notification webhook
- [x] `php-api/endpoints/membership-secrets.php` - separate file so a
      deploy never merges `app-secrets.php`
- [x] **Nothing Apple sends is trusted.** A notification is a doorbell:
      it names a transaction, and the server then asks Apple directly
      over TLS. Forged and replayed notifications achieve nothing.
- [x] Schema created **lazily**, on first use - deploying runs no DDL

### Tests

- [x] 41 Flutter tests across config, sync and renewal; 976 passing
      overall with 6 known pre-existing failures
- [x] `php tools/membership-test.php` - 33 checks on the entitlement
      rules, no database or network needed

---

## Blocked: the Paid Apps Agreement

**Status: Pending User Info.** Apple's own definition: *"You've signed an
agreement, but it's not in effect because you haven't finished providing
required information."* Apple is waiting on you, not reviewing.

**An inactive agreement means StoreKit returns zero products.** Nothing
below this line can be tested until it is Active.

- [ ] Find out who the **Account Holder** is - only they can finish it
- [ ] Contact info: senior management, financial, technical, legal
- [ ] Bank account, and let it verify
- [ ] Tax forms - for a UK entity that means a US form (W-8BEN-E)
      alongside the UK information
- [ ] Watch it go **Pending User Info -> Processing -> Active**

App Store Connect -> **Business** -> **Agreements** -> Paid Apps row.
Entering it is twenty minutes; Processing afterwards is days, and a bank
verification can add more. It was signed on 4 November, so it has been
sitting incomplete for three weeks.

---

## Before you can submit

### Blocker found while writing this

- [ ] **The paywall's Terms and Privacy links are dead.**
      `subscribe_screen.dart` points at `https://www.drivelife.app/terms`
      and `/privacy`. **The domain does not resolve at all** - both
      return a connection failure, and they are the only two URLs of
      their kind in the app.

      Apple requires functional links to an EULA and a privacy policy on
      any subscription paywall, and checks them. This is a guaranteed
      rejection.

      `https://www.carevents.com/uk/privacy-policy/` returns 200 and
      could stand in. `carevents.com/uk/terms-conditions/` returns 404,
      so the terms page needs finding or writing.

### Product metadata

- [ ] **Review screenshot** for each of the three - the one people
      forget. You can take it from the local StoreKit build.
- [ ] Display name and description per product, per locale
- [ ] Subscription group display name
- [ ] **Confirm the real SuperCharged price.** £99.99 is a placeholder I
      invented, in both `ios/DriveLife.storekit` and
      `lib/models/subscription_plan.dart`. Whatever is in App Store
      Connect wins at runtime - the paywall shows the store's own price
      string - but the local file and the screenshots will be wrong.
- [ ] Tax category for subscriptions
- [ ] Decide **Family Sharing** - currently off in the local file
- [ ] Decide **introductory offer / free trial** - currently none
- [ ] Locale: everything is `en_GB` only today

### Submission

- [ ] **Add for Review** on the subscriptions
- [ ] Upload a build and attach it to the app version
- [ ] Attach the subscriptions to that same version - *"Your first
      subscription group must be submitted with a new app version"*
- [ ] Set the version to **manual release**, so approval does not
      publish it while you are still testing
- [ ] Update App Privacy for purchase data

**Add for Review does not make anything live.** Products become
purchasable only when the version carrying them is approved *and*
released.

---

## Sandbox, once the agreement clears

- [ ] Create a **sandbox tester** account
- [ ] **Set the scheme's StoreKit Configuration back to `None`** - a
      scheme left pointing at the local file silently serves those
      products instead of the real ones, which looks exactly like App
      Store Connect being broken and has cost people days
- [ ] Sign the device into the sandbox account
- [ ] Confirm products load from App Store Connect
- [ ] Buy, cancel, resubscribe, let one renew (sandbox renews fast)
- [ ] Confirm the three UI states against a real subscription
- [ ] Test on TestFlight specifically - it uses sandbox too

Worth knowing: whether a **first ever** subscription group can be fetched
in sandbox before it has shipped with a build is disputed. Some sources
say review is not needed; Apple forum threads report first groups
returning nothing until attached to a version submission. If sandbox
returns an empty list with everything else correct, that is probably why.

---

## Before real money changes hands

Today the tier comes from **what the device says**. That is fine while
the only thing it controls is whether adverts show - a rooted phone gets
an ad-free feed and that is the whole loss. It stops being fine the
moment a benefit is worth something.

- [ ] Deploy `membership.php`, `membership-apple.php`,
      `membership-secrets.php`, plus the include lines **added by hand**
      to the live `app-endpoints.php` (there is no `app-endpoints-LIVE`
      to diff against, so do not upload the local copy)
- [ ] Generate an **In-App Purchase key**: App Store Connect -> Users and
      Access -> Integrations -> In-App Purchase. **Not** the Sign in with
      Apple key - different key, and revoking one would break both.
- [ ] Fill in issuer id, key id and the `.p8` into
      `membership-secrets.php`
- [ ] Set the **App Store Server Notifications V2 URL**, production
      *and* **sandbox** - they are configured separately, and forgetting
      the sandbox one is why testing appears to do nothing
- [ ] **Build the Dart client** for `/membership/me` and
      `/membership/link` - this does not exist yet, so the endpoints are
      currently unreachable from the app

  > One rule when building it: a failed or unreachable `/membership/me`
  > must leave the server slot **null**, never call `set(none)`.
  > Otherwise a network blip overrides the store's correct "yes" and the
  > membership flickers off. `MembershipProvider` is already shaped for
  > this; the client has to respect it.

- [ ] Decide whether to attach an **`appAccountToken`** at purchase -
      a UUID tying the Apple transaction to a DriveLife user. It makes
      webhook-to-user matching trivial instead of a lookup that fails for
      anyone who bought before you recorded them.
- [ ] Report the purchase to the server **as part of buying**, not after

---

## Still open

- [ ] **What is actually gated?** Right now: adverts, and nothing else.
      Every listed benefit - badge, early access, partner discounts - is
      either cosmetic or not built. Worth deciding before launch which
      are real on day one, because the paywall already promises them.
- [ ] `/subscribe` is registered unconditionally in `routes.dart` and
      reachable by name. Fine while there is nothing to buy; decide
      whether to gate it behind `kDebugMode` until launch.
- [ ] **Merge `main` into this branch.** `main` has commit `2a497a7`,
      the garage AI scan fix. A TestFlight build cut from here without it
      still has that bug.
- [ ] Grandfathering: `lib/models/pro_limits.dart` exists and is
      deliberately unused, because every benefit is additive today. It
      becomes relevant the moment one is not.
- [ ] An admin screen for the `dl_membership_config` option - editing it
      means WP admin or WP-CLI at the moment

---

## Not doing yet: Google Play

Deliberate. What already works on both, and what would be left:

**Already cross-platform:** the whole app-side model, `FeedAdSlots`, the
remote config, the paywall, the membership provider, and auto-renew
detection - Play puts `isAutoRenewing` on the purchase, so Android
needed no native code at all.

**Would be needed:** products in Play Console; a Play Developer API
service account - the existing `service-account-file.json` is a Firebase
messaging account and would need Play access granted; Real-time
Developer Notifications over Pub/Sub; and the Google half of
`dl_membership_link`, which currently returns 501 rather than pretending.

The server schema already carries `store` and handles `google` throughout,
so none of this is a rewrite.

---

## Things that cost time, written down so they do not again

- `flutter run` ignores the scheme's StoreKit configuration. Launch from
  Xcode.
- Local StoreKit testing sends **no** App Store Server Notifications -
  nothing reaches Apple. Sandbox does, to the separate sandbox URL.
- A local StoreKit purchase **cannot** be validated server-side. Its JWS
  is signed by Xcode's test certificate, not Apple's, so the server
  correctly answers "not found".
- "Cancelled" still entitles somebody. Cancel on day 2 of a year, keep it
  for 363 more days. Both the app and the server make this distinction;
  anything new must too.
- Apple reports price in **milliunits** - 4990 is £4.99. Divide by 10.
