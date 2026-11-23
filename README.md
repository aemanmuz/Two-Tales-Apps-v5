# Two Tales Business Admin V3.1 — Member Loyalty Rewards

**Original V3 interface retained** (no Modern Café redesign). This upgrade is based on the **V3 Customer ID Hotfix** ZIP uploaded on November 23, 2026.

## Business rules

- **Member purchases:** Every completed POS purchase earns `floor(amount actually paid in RM)` points. Examples: RM12.00 → 12 points; RM12.90 → 12 points; RM0.90 → 0 points. Walk-ins earn none.
- **Point redemption:** Points are **NOT** a cash equivalent at checkout. Direct points-for-RM POS discount is disabled in both UI and the upgraded `tt_checkout` SQL function.
- **Gifts:** Members can spend their points on configured gifts/variants, with stock checking and atomic cloud redemption as in V3.
- **Reward vouchers:** Voucher management has an optional **Points to claim** field. With a positive points cost, a voucher can be claimed by an eligible existing member. Claiming deducts points immediately, creates one single-use voucher claim, and records history. The member selects the claimed voucher at checkout, which uses the claim once. **0 points** means the existing free/general POS voucher behavior.
- **Historic orders:** Earlier V3 orders do not contain `pointsEarned` and retain the historic **1 per RM10** calculation. This avoids retroactively changing customer balances. New POS sales include an explicit `pointsEarned` field calculated at **1 per RM1**; the old cash-redemption records remain for audit/history. Contact us before changing this policy if the business wants **retroactive 1:1 credit**.
- **Refunds:** A voided POS sale reverses the points awarded by that sale. If a claimed voucher was used for the voided sale, the claim returns to `Claimed` (subject to any validity/expiry rules).

**START HERE: [DEPLOY_V3_1.md](DEPLOY_V3_1.md).** Run the **new** `supabase/upgrade_v3_1_loyalty_rewards.sql` only after backing up an existing, working V3 installation. Do not run `upgrade_v3_gifts_vouchers.sql` again if it was already applied.

## Preserved

Existing V3 interface/CSS, Customer ID hotfix, GitHub Pages, PWA, POS stock logic, customer history, gift catalogue, existing vouchers, Supabase Auth, orders and analytics.

## Files

- `index.html`: Original V3 interface + updated loyalty features (Supabase public configuration intentionally empty)
- `supabase/upgrade_v3_1_loyalty_rewards.sql`: Additive PostgreSQL migration; new voucher claim RPC and updated sale, gift, refund and projection functions
- `supabase/verify_v3_1.sql`: Read-only checks after migration
- `DEPLOY_V3_1.md`: Safe deployment and full acceptance checklist
- Existing V3 files and deployment instructions retained for reference; PWA cache version bumped

## Operational and security notes

The current architecture is still **single-account / authenticated-admin trust model with a JSON snapshot**, so this migration is **not a fine-grained staff role or tamper-proof ledger security upgrade**. A powerful authenticated account with `tt_save_state_v2` access can still alter state. Keep the admin credentials protected and do not give them to untrusted staff. Use Supabase RLS appropriately and continue security hardening later.

Do not upload private credentials, service-role keys, passwords, database exports or customer records into GitHub Pages. All Supabase keys in the ZIP are **blank**.

Browser tests used simulated Supabase responses; **the SQL has not been executed against your production database**. Validate migration, test on a copy/staging project, and only then move live. The ZIP contains no customer data and does not itself touch your database.
