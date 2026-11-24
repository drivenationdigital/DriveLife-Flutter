# DriveLife.storekit

Local StoreKit testing. **Nothing here touches Apple's servers.**

## What it is

Xcode can run StoreKit against a local file instead of the App Store.
Products are defined here, purchases are simulated on the device, and
no Apple account, no sandbox account and no network call is involved.

It exercises the real StoreKit APIs — purchase, cancel, restore,
renewal, refund, failure — so it is a genuine test of the app's code,
with nothing leaving the machine and nothing that can reach a customer.

This is the right first test. Sandbox comes after it.

## Turning it on

**Already wired.** The shared Runner scheme points its Run action at
this file (`StoreKitConfigurationFileReference` in
`Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`), so a plain
`flutter run`, or Run from Xcode, uses it with no further setup.

To confirm or change it in Xcode, with `ios/Runner.xcworkspace` open:

1. **Product → Scheme → Edit Scheme → Run → Options**
2. **StoreKit Configuration** → `DriveLife.storekit`

Because the setting lives in the *shared* scheme it is committed, so
it applies to everyone who checks the repo out — which is what makes
local testing the default rather than something each person remembers
to switch on.

**Turn it back to `None` before doing any sandbox testing.** A scheme
left pointing at this file silently serves these products instead of
the real ones, which looks exactly like App Store Connect being broken
and has cost people days.

## What it gives you

While it is running, Xcode shows a **StoreKit Transaction Manager**
(Debug → StoreKit → Manage Transactions). From there you can, on
demand and instantly:

- approve or decline a purchase
- force a renewal
- issue a refund
- expire a subscription
- make a purchase fail

Those are the paths that take a test account and real waiting against
sandbox. Here they are a menu item each.

The `settings._storeKitErrors` block above can also force specific
failures — Load Products, Purchase, Verification — which is how to see
what the app does when the store is simply unreachable.

## What is in it

| product | duration | level | price |
|---|---|---|---|
| `drivelife_plus_monthly` | 1 month | 2 | £4.99 |
| `drivelife_plus_yearly` | 1 year | 2 | £44.99 |
| `drivelife_supercharged_yearly` | 1 year | 1 | £99.99 |

`groupNumber` is the level: **1 outranks 2**, matching App Store
Connect. Plus monthly and yearly share level 2, so switching between
them is a crossgrade rather than an upgrade.

## One thing to correct before relying on it

**The SuperCharged price is a placeholder.** £99.99 was invented to
make the tier visible. Replace it with the real one, here and in
`lib/models/subscription_plan.dart`.

The product id is settled: `drivelife_supercharged_yearly` was
confirmed against App Store Connect on 24 November 2026. The console
had only truncated it to `drivelife_supercharged_year…`, which is why
it previously read as a guess.

Prices here do not have to match App Store Connect for the app to work
— this file is only ever a local simulation — but they should, or the
screenshots you take from it will be wrong.

## What the app does with it

`StoreSubscriptions` (lib/services/store_subscriptions.dart) is the
real implementation behind the paywall's `SubscriptionService`, and it
is now the default — `FakeSubscriptions` is only reachable by being
handed in, by the demo screen and the tests. So with this file
selected, the paywall queries these products, shows these prices, and
runs a real StoreKit purchase against them.

**What it still does not do is grant membership.** The store tells this
device what it believes; nothing has checked that with Apple. The tier
that gates features comes from `MembershipProvider`, which is still set
by the demo screen — see docs/pro-membership-design.md §2. Testing a
purchase here proves the FLOW works, not the entitlement.

## What this file is NOT

It is not a submission, not a configuration of anything real, and not
connected to the products in App Store Connect. Editing it changes
nothing outside this repo. Deleting it breaks nothing.
