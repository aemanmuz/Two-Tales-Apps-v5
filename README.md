# Two Tales Business Admin v2.0 — Reliability, Loyalty, Receipts & Analytics

This package includes the **RLS SQL-editor syntax fix (18 November 2026)**. If the prior SQL failed with `unterminated dollar-quoted string` near `$policy$`, open a new Supabase SQL Editor query and run the **entire** `supabase/upgrade_v2.sql` in this package. Do not run a highlighted selection, and do not paste any dashboard-generated RLS statements inside a PL/pgSQL block.

This is a **direct upgrade of your existing GitHub Pages + Supabase + PWA project**. The original dark-chocolate / beige design, product variants, inventory, calendar, staff, customer history, reports, authentication, and installable PWA are retained.

**IMPORTANT:** This ZIP is ready for deployment **after you configure the same Supabase URL/key and run the included SQL migration**. I do not have access to your Supabase account and cannot run the migration for you. Existing data is not packed into this ZIP; it remains in your existing Supabase project.

## Deployment — follow this exact order

1. **Pause live POS operations** and download your existing site's **Backup data** JSON before any changes. Also save a copy of the currently deployed `index.html`, and ideally export your `public.business_state` table in Supabase. Do not replace the project or create a new Supabase project.
2. Open the **existing Supabase project** at https://supabase.com/dashboard and go to **SQL Editor → New query**. Open `supabase/upgrade_v2.sql` from this ZIP. Paste and run the entire SQL file. It runs as one database transaction. The script creates new normalized `tt_*` tables and RPCs, backfills them from each existing `business_state` row, and leaves original payloads, versions, Auth accounts and the old `save_business_state` RPC untouched.
3. Run `supabase/verify_v2.sql` in SQL Editor. Compare the old versus new counts for products, orders, customers and staff. If any database migration fails, **do not deploy the new site**; the script's transaction should roll back, leaving existing records in place. Resolve the error from the Supabase SQL Editor output.
4. Open the supplied `index.html` in VS Code. At the top of its main script, copy **the existing** `SUPABASE_URL` and `SUPABASE_KEY` values from your working site into the two blank configuration constants. Use only the publishable/anon key: **never a secret or `service_role` key**.
5. In your existing GitHub Pages repository (`aemanmuz/Two_Tales_Business_Apps` if unchanged), replace `index.html`, `manifest.webmanifest`, `sw.js`, `offline.html`, and the full `icons` folder with their files from this ZIP. Keep your existing optional `qr.png` at the repository root if you use QR PAY. **Do not upload the SQL or test scripts to GitHub unless you want them versioned as project documentation.**
6. Commit to the same GitHub Pages branch, then reload the site. The existing PWA remains installable; if Chrome/Edge shows the previous version, close/reopen the app and hard-refresh the installed PWA. Log in using the **same Supabase Auth account** as before.
7. Confirm your old products, member records, order history, staff, inventory and reports are present. Run the test checklist below with **a small test sale first**, ideally on two devices logged into the same business account.

> **No data wipe is required.** SQL migration is additive, and the original `business_state` table remains the compatibility source of truth. The new `tt_*` relational tables are synchronized, read-only projections for reporting and future migration; they are not independently writable masters. This preserves backward compatibility while POS transactions become atomic server-side RPCs.

## What's new

| Priority | Implemented |
|---|---|
| POS and customer reliability | Customer selection by stable ID (not name), authoritative price/stock validation, optimistic version conflict detection, serialized ordinary writes, server-side atomic checkout, duplicate-request/idempotency protection, seller attribution |
| Supabase restructure | New normalized product, variant, customer, order, order-item, payment, staff, inventory, cash, and loyalty-ledger tables; migration backfill; RLS owner-scoped reads; automatic projection syncing from legacy snapshot (even older app writes) |
| Advanced POS & receipts | Product search, fixed/% discounts, cash received & change, QR payment confirmation, optional sale note, printable 80mm-style receipts, receipt reprint, order search, audited void/refund with automatic stock restoration |
| Customer loyalty | 1 point earned per RM10 paid on **new eligible completed member POS sales**; 1 point redeems RM0.10; customer points balance reflects earning, redemptions, cancellations and configured opening points |
| Analytics dashboard | 30-day collections mini-chart, advanced 7/30/90/365-day analytics, average order value, discounts, gross margin estimate, pending balances, payment breakdown, top products/members, repeat customer rate, CSV exports |

## Transaction integrity and safety notes

- **Save behavior:** Every ordinary edit is written to `tt_save_state_v2` using a version guard. If another device has changed the same business state, the save is **rejected rather than silently overwriting** the newer data. Use **Backup data** or **Export failed-save recovery**, then reload and reconcile before retrying.
- **Checkout behavior:** `tt_checkout` checks stock, price, seller, customer, discount and loyalty **inside a single Supabase database transaction** and commits the new order, stock movement, cash entry and normalized projections together. If a response times out, the sale form retains a single request reference for a safe idempotent retry. Check Orders before retrying if connection status is uncertain.
- **Voiding:** A finalized POS order is not deletable/editable through normal order management. **Void & refund** asks you to confirm that the customer has **already been refunded**; the system does not send money through a bank, QR provider or gateway. It changes status, records a cash outflow, restores available stock (if product/variant still exists) and reverses earned/redeemed points. Keep products/variants in your catalogue while active sales reference them.
- **Loyalty migration:** Old sales are **not retrospectively awarded loyalty points**. If you already have a separate previous loyalty programme, enter the agreed opening points in Edit Customer manually. Legacy `spent` continues to represent **pre-recorded historical spending only**; total spent is computed from paid non-cancelled orders plus this balance.
- **Reports:** Revenue and collected payments are different concepts. Analytics charts use payments attached to the order date; they are **not a bank reconciliation or payment-settlement ledger**. Profit is an estimate because tax, discounts, operating expenses, and missing historical costs can change results.
- **Permissions / multiple devices:** Data remains separated by `auth.uid()` as in the original app. Different Auth accounts do **not** automatically share one business dataset. Using the same authorized login across devices sees the same records.
- **QR PAY:** Add `qr.png` at the repository root if you want to display the static merchant QR image. An operator must tick the payment confirmation box after verifying receipt. This is **not** automated payment verification.
- **Offline:** The PWA is still installable but business transactions require connectivity. The service worker **does not cache private business data or Supabase responses**; it only caches offline information and static icons/manifest.

## Test checklist (use safe test records)

- [ ] Log in and verify old orders, customer spending, staff and products are unchanged.
- [ ] Create a member with a unique name. Select them in POS, complete a small Cash sale and ensure Customer History total spent and loyalty points update.
- [ ] Repeat with QR PAY; check confirmation and receipt printing / reprinting.
- [ ] Apply an RM discount, a percentage discount, and a point redemption; check receipt totals and remaining points.
- [ ] Attempt to sell more stock than available from a different device. Confirm the database rejects the conflicting checkout.
- [ ] Void and **actually refund** a test POS sale; check restored stock, cancelled history, reversed loyalty and refund entry under Reports.
- [ ] Verify the old legacy order data remains visible and `supabase/verify_v2.sql` shows matching counts.
- [ ] Verify `Dashboard` and `Analytics` charts and CSV exports; test Chrome/Edge PWA installation again.

## Local syntax/domain checks

Run `node tests/domain_smoke.cjs` from the extracted project directory (Node 18+). These are **mocked domain tests** of the HTML JavaScript; they do not validate your live database or real Supabase SQL execution.

## Rollback

Re-deploy your previously backed up site files to the **same GitHub Pages repository**. The original `business_state` and Auth rows are not destroyed by this upgrade. The new `tt_*` tables can remain as inert projections without affecting legacy site operation. **Do not drop or truncate tables to roll back**. Always keep your pre-migration backup until you have reconciled your live sales.
