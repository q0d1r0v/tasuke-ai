# In-app products

The single source of truth for what must be configured in App Store Connect and
in the Play Console. `lib/core/purchases/product_ids.dart` holds the same two
strings, and `test/app/platform/store_products_test.dart` asserts this file and
that file agree — so a typo surfaces as a red test rather than as a paywall that
renders nothing on one platform.

App: **Tasuke AI** — `uz.digitalgroup.tasuke` — 1.0.0+9

## The two products

| Product ID           | Period | Price (USD) | Level | Notes                       |
| -------------------- | ------ | ----------- | ----- | --------------------------- |
| `tasuke_pro_yearly`  | 1 year | $39.99      | 1     | $3.33/mo equivalent, save 33% |
| `tasuke_pro_monthly` | 1 month| $4.99       | 2     |                             |

Both belong to one subscription group / one Play subscription family:

- **Group name:** `tasuke_pro`
- **Group display name:** Tasuke Pro

There is **no introductory offer and no free trial** on either product. The free
tier (1 capture a day, spoken or typed, forever) is the trial; adding a 7-day trial on top
of it would give a new user two overlapping "free" stories and makes the
`EntitlementStatus.free` → `pending` → `proActive` sequence much harder to
reason about.

## Levels, and why the order matters

⚠️ Yearly is **level 1**, monthly is **level 2**. Lower number = higher tier.

That ordering is what makes monthly → yearly an **immediate upgrade** (charged
now, prorated, Pro never lapses) and yearly → monthly a **deferred downgrade**
(takes effect at the next renewal, the user keeps what they paid for). Swap the
two numbers and a user upgrading to yearly is instead told the change will apply
"at the end of the period" — they have paid and got nothing, which is a refund
request and a one-star review.

The same ordering is encoded in `ios/Runner/Tasuke.storekit` (`groupNumber`), so
the simulator behaves like the store.

## Apple — App Store Connect

- Subscription group: `tasuke_pro`
- Reference names: `Tasuke Pro Yearly`, `Tasuke Pro Monthly`
- Price tier: USD 39.99 / USD 4.99, all territories at the store's automatic
  equivalents. ⚠️ The app never renders a hardcoded price — `SubscriptionPlan.price`
  is the store's own localised string, and a guard test forbids a currency
  literal under `lib/features/subscription/`.
- **Billing grace period: ON, 16 days** (App Store Connect → the app →
  Subscriptions → Billing Grace Period). ⚠️ One app-wide setting that covers
  both plans; Apple offers only 3, 16 or 28 days and has no per-product value.
- Family Sharing: **off**.
- Local testing uses `ios/Runner/Tasuke.storekit`, wired into the Runner scheme.
  That file is a simulator fixture; it does **not** configure the real store.

## Google — Play Console

Play models this as one subscription per product id with base plans underneath.

| Subscription ID      | Base plan ID      | Tag       | Renewal type   |
| -------------------- | ----------------- | --------- | -------------- |
| `tasuke_pro_yearly`  | `yearly-autorenew`| `yearly`  | Auto-renewing  |
| `tasuke_pro_monthly` | `monthly-autorenew`| `monthly`| Auto-renewing  |

- **Base plan tags are load-bearing.** `in_app_purchase_android` returns one
  `ProductDetails` per base-plan/offer combination, and the tag is the only
  stable way to tell them apart. Changing a tag after launch orphans the
  paywall's mapping.
- **Grace period:** 7 days (monthly), 14 days (yearly).
- **Account hold:** 30 days, after the grace period.
- Both grace states must keep Pro unlocked — `Entitlement.isPro` already treats
  `proGrace` as entitled. A grace-period subscriber has a failing card, not a
  cancelled subscription.
- Proration mode for monthly → yearly: **charge prorated price / immediate**.
  The app never switches plans itself: a subscriber's "Manage subscription"
  opens the store's own subscription page, so this setting applies to changes
  the user makes there.

## Manage-subscription links

Opened by the paywall's "Manage subscription" button (what a subscriber sees
instead of "Subscribe"), from `ProductIds.manageUri`:

- Apple: `https://apps.apple.com/account/subscriptions`
- Google: `https://play.google.com/store/account/subscriptions?sku=<productId>&package=uz.digitalgroup.tasuke`

Both are `https`, which is why `AndroidManifest.xml` needs its `<queries>` block —
without it `canLaunchUrl` returns false and the button does nothing.
