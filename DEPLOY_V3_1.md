# Deploy V3.1 — Loyalty points, gift rewards and member voucher claims

**For a working Two Tales V3 Customer ID Hotfix installation only.** This update uses the original V3 design (no café theme), and changes business logic plus Supabase SQL functions. The migration does **not** clear existing customers, sales, products or rewards.

## 1. Before doing anything

1. Pause live POS transactions and ask other staff to close older PWA tabs. Do not run overlapping V3 and V3.1 clients for live checkout.
2. Verify that the current Supabase project uses the working V3 Gifts & Vouchers schema (`tt_redeem_gift`, `tt_checkout`, `tt_void_sale`, `tt_save_state_v2`). Do not run a fresh start/reset SQL migration.
3. Back up **all** `public.business_state` records including `payload` and `version`, using your normal secure Supabase backup/export procedure. Confirm the backup can be restored. Protect the export because it contains customer information. Do **not** place it in your public GitHub repository.
4. If possible, restore that backup into a private staging Supabase project and test there first. Save the current production `index.html` and SQL function definitions for rollback. Make a record of the currently deployed Git commit.

## 2. Apply SQL migration first

In **the existing V3 project's** Supabase SQL Editor, run the **complete file**:

`supabase/upgrade_v3_1_loyalty_rewards.sql`

Run the entire script, not selected lines. It is wrapped in `BEGIN; ... COMMIT;`. It creates a read-only `tt_voucher_claims` projection and `tt_claim_voucher` RPC, changes the point earning rule for **new** POS orders, makes direct POS points-to-cash redemption invalid, and updates gift claims and void/refund handling.

Next, run `supabase/verify_v3_1.sql` and confirm required SQL functions exist. The migration must **not** be followed by the V2/V3 fresh-start SQL or an old migration.

**Critical:** Do not deploy the updated frontend before SQL is in place. When upgrading, avoid live transactions until both frontend and backend match.

## 3. Deploy on GitHub Pages

1. Save the public Supabase project URL and **publishable/anon** key from your **existing, working** `index.html` (do not share them in this chat). Put them in the two top-of-script configuration strings in the new `index.html`.
2. Never use a Supabase secret/service-role key in HTML/JavaScript. `.gitignore` does not hide secrets in a public webpage.
3. Upload the new `index.html`, `sw.js` and the supporting files to the same GitHub Pages path. Keep existing assets like `qr.png` if your checkout uses them.
4. Check the deployed URL over HTTPS. Close/reopen any installed PWA, or refresh with browser cache cleared if the old version persists. The PWA cache name has been bumped to V3.1.

## 4. Acceptance tests on staging (not with live customer transactions)

- [ ] Customer count, transaction history, products, gift catalogue and vouchers match the pre-upgrade backup.
- [ ] An existing member starts with the **same** points balance as before the upgrade. Previous completed orders have not been retroactively recalculated at 1:1.
- [ ] A new RM12.90 completed member sale awards **12 points**; a RM50.00 sale awards **50 points**; a walk-in sale awards **0 points**.
- [ ] The POS **does not** show a field to exchange points directly for RM. Sending `redeemPoints > 0` to `tt_checkout` is rejected by SQL.
- [ ] Set up a gift costing 20 points with stock 1. Claim for a qualifying member; 20 points disappear and stock decreases by one. A second claim when out of stock fails.
- [ ] Create a **RM5 discount voucher for 40 points**. Claim for an existing member; points decrease by 40, voucher appears for that member at POS, and does not appear for another member or walk-in.
- [ ] Use the claimed voucher once. It gives RM5 off, marks the claim **Used**, and cannot be applied again. The new sale earns points on the **amount actually paid** after discounts.
- [ ] A voucher with **0-point cost** remains a regular free voucher and follows existing audience/limits rules.
- [ ] Gift redemption must also account for already-claimed voucher points when checking member balances.
- [ ] A second click/retry with the same voucher claim requestId does not deduct points twice.
- [ ] Attempt a claim with insufficient balance, inactive/expired voucher, wrong assigned member or exceeded limit; all must fail.
- [ ] Void the test sale; stock and earned points reverse, the voucher claim becomes **Claimed** again (if it was used in the sale), and the refund appears.
- [ ] Confirm the customer ID hotfix still allows rapid customer CSV imports without duplicated IDs.
- [ ] Confirm no browser JavaScript errors and that dashboard, POS, gifts, vouchers, customers, analytics, reports and the installed PWA load.

## 5. Production caveats

- These SQL functions and all other cloud writes have **not** been executed here against your Supabase instance. The browser acceptance test used a mock backend, so do not assume production is proven safe until staging SQL tests pass.
- The app still uses `business_state` as its canonical JSON snapshot. Existing authenticated account privileges (`tt_save_state_v2`) are broad; it remains an admin-trust system, not a secure multi-cashier tenancy model.
- If a migration fails, its outer transaction should roll back automatically. If a later issue happens, **pause sales** before considering a rollback; restore both frontend and corresponding SQL function definitions, and reconcile any real transactions that occurred after the backup. Do not simply overwrite newer live data with an old snapshot.
- A voucher claim deducts points at claim time; expiry does **not** currently auto-refund those points. Do not publish short-lived reward vouchers without a clear business policy for expired unused claims.
