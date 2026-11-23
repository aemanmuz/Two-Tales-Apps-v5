# Changes from V3 Customer ID Hotfix to V3.1

- Kept the exact original V3 HTML/CSS visual design and all existing sections.
- Retained previous Customer ID hotfix logic and PWA assets.
- Replaced live POS award rate with **one whole loyalty point per RM1 actually paid** for completed member sales, recorded as explicit `pointsEarned` on new orders.
- Kept historic order credits on the original 1 point per RM10 rule (no automatic retroactive recalculation).
- Removed direct points-as-RM discount controls and calculations from the POS. The server rejects any new nonzero `redeemPoints` request.
- Retained and updated existing gift redemption to account for voucher points already committed.
- Introduced configurable `pointsCost` for vouchers, an existing-member redemption modal and single-use `voucherClaims` history.
- Reward voucher can only be used when a valid unused claim belongs to the selected member. Completing checkout marks the claim Used atomically with sale creation.
- Void/refund restores the Used voucher claim to Claimed; the claimed points remain spent since the claim remains available.
- Added an SQL `tt_claim_voucher` RPC, protected read-only claims projection, updated gift, checkout, void and V2 order projection functions.
- Analytics points redeemed includes gift and voucher claims within selected reporting dates.
- V3.1 PWA cache version bump.

**Limits:** SQL functions not exercised against user's real database. Existing broad authenticated admin snapshot editing remains and is not fine-grained multi-user permissioning. See DEPLOY_V3_1.md.
