# Two Tales Business Admin V3 — deployment checklist

## 0. What is included
- **Gifts & Rewards:** separate gift catalogue, base gift and named variants, points cost, stock, enabled/disabled state, member redemption and redemption history.
- **Vouchers:** general POS vouchers or vouchers assigned to a specific member; percentage/fixed RM discount, start/expiry date, total usage limit, optional per-customer usage limit and enable/disable switch.
- **POS integration:** select an eligible voucher during a sale; Supabase calculates and validates voucher discount and prevents overuse when completing the sale. The receipt records voucher code and saving.
- **Existing loyalty:** earned points minus POS point-spend minus gift redemptions. Gift claims deduct stock and points in one database transaction.

## 1. Backup FIRST (no database reset)
1. Sign in to the CURRENT site; press **Backup data** in the sidebar. Store the JSON in a private local folder, **not in GitHub**.
2. In Supabase > SQL Editor, run `supabase/backup_before_v3.sql`. Export the result to a secure file if desired.
3. For important production records, also use Supabase's database backup/export facilities according to your plan. Keep at least one tested copy.
4. Record your existing product, customer and order counts. Do **not** run `fresh_start_v2.sql` again: it deletes business data.

## 2. Supabase upgrade — MUST happen before GitHub deployment
1. Open the **same existing Supabase project** already used by your V2 website.
2. SQL Editor > New query > paste **all** of `supabase/upgrade_v3_gifts_vouchers.sql` and run (no highlighted subset).
3. It is wrapped in `BEGIN; ... COMMIT;` so an SQL failure should roll back that migration transaction.
4. SQL Editor > New query > run `supabase/verify_v3.sql`. Confirm four new tables, the new redeem RPC and all older products/customers/orders still exist. Empty new reward/voucher tables are normal at first.
5. In Supabase Authentication, your existing email account remains unchanged.

## 3. GitHub Pages deployment (same repository and link)
1. Download and extract this ZIP locally. Open `index.html` in VS Code.
2. Copy the same *public* `SUPABASE_URL` and `SUPABASE_KEY` values from your old working `index.html` into the new file. This ZIP intentionally leaves them blank. Use **only** the anon/publishable key. **Never** place service_role key or DB password in client JavaScript.
3. Back up your current GitHub repository/branch. Add the new/updated files (`index.html`, `sw.js`, `manifest.webmanifest`, `offline.html`, `icons/`, `.gitignore`). You can also commit the documentation and SQL scripts; **never commit actual customer data/backups/secrets**.
4. On GitHub website: open your repository > **Add file > Upload files**. Drag in the updated site files and directories (include `.gitignore` using a local Git client if browser hidden-file upload omits it). Commit to the branch and folder configured in **Settings > Pages**. Alternatively use `git add -A`, `git commit -m "V3 gifts vouchers"`, `git push` from your local clone.
5. Confirm GitHub Pages has published the new commit. Refresh the browser using Ctrl+Shift+R. If your installed PWA remains old, close and reopen it; check the browser's Application > Service Workers and unregister an obsolete worker if necessary.
6. Keep `qr.png` and any other custom assets from your old repository. This package doesn't include your merchant payment QR.

## 4. Acceptance tests (use TEST data first)
1. Sign in with your existing email account. Confirm historical products, customers, orders and loyalty balance are intact.
2. Add a gift with 2 variants, 5 and 10 items in stock, and 50/100 points cost. Save, refresh cloud and reload; confirm the variants persist.
3. Create or select a test member with enough points (set starting points for TEST customer only), redeem a gift, refresh. Confirm points are deducted ONCE, gift stock decreases by ONE, and redemption history is saved.
4. Create a general `WELCOME5` RM5 voucher. POS: purchase an item using the voucher. Check total and receipt; reload and verify the voucher usage count.
5. Create a member-only `MEMBER10` 10% voucher. Select a different customer/walk-in: should not appear; select the assigned customer: should appear.
6. Test expired voucher, disabled voucher, insufficient stock/points, no customer selection, and max-redemptions reached.
7. Test a sale without voucher to confirm POS still works, and check Reports/Analytics.
8. Void a test order and inspect resulting voucher usage: this app considers **only Completed** orders as consumed. A void restores voucher availability. Physical refunds must still be handled separately.

## Notes and known limitations
- **Single-account workspace:** records are scoped to the signed-in Supabase `auth.uid()`. Different email users do NOT automatically share the same business dataset. Do not assume a multi-user organisation/roles system.
- **Legacy snapshot model:** the V2 `tt_save_state_v2` function saves entire JSON business state. The V3 catalogue and vouchers live inside that JSON and are mirrored to new indexed tables. The server-side checkout and gift redemption validate points/stock/vouchers under a row lock, but the broader snapshot editor model is not a tamper-proof staff permission system. Restrict login to trusted administrators until role-based server authorization is built.
- **Gift redemption:** a completed redemption is an audit record; there is no refund/reversal button in this version. Correct mistakes through an audited future reversal process, rather than editing balances without a record.
- **POS discount:** the existing manual discount, then voucher, then optional points spend apply in that order; percentage voucher applies to the subtotal after manual discount.
- **No secret in the frontend:** `.gitignore` prevents tracking local secret files, but cannot hide a key already pasted into publicly served HTML. Supabase's anon/publishable key is designed to be public; security depends on RLS/RPC permissions. Do not store service_role secrets in the repository or browser.
- **Production checkout:** no live Supabase instance was accessible for tests. Run all acceptance tests before handling actual money.
