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

In Xcode, with `ios/Runner.xcworkspace` open:

1. **Product → Scheme → Edit Scheme → Run → Options**
2. **StoreKit Configuration** → `DriveLife.storekit`
3. Run on a simulator or device

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

## Two things to correct before relying on it

**The SuperCharged product id is a guess.** App Store Connect showed it
truncated as `drivelife_supercharged_year…`. If the real one differs,
fix it here AND in `lib/models/subscription_plan.dart` — a mismatch is
a product that never loads.

**The SuperCharged price is a placeholder.** £99.99 was invented to
make the tier visible. Replace it with the real one.

Prices here do not have to match App Store Connect for the app to work
— this file is only ever a local simulation — but they should, or the
screenshots you take from it will be wrong.

## What this file is NOT

It is not a submission, not a configuration of anything real, and not
connected to the products in App Store Connect. Editing it changes
nothing outside this repo. Deleting it breaks nothing.
