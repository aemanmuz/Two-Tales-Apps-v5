# TWO TALES V2 — FRESH START

1. IMPORTANT: This deletes all Two Tales app business data (customers, products, orders, staff, cash, inventory) in the CURRENT Supabase project, while preserving Supabase Auth users / email login. If you might need the old data, export it first.
2. Supabase Dashboard -> EXISTING project -> SQL Editor -> New query.
3. Open `supabase/fresh_start_v2.sql`, copy THE WHOLE FILE, and Run. Never run only a selection.
4. Open another query, run `supabase/verify_fresh_start.sql`. You should see `business_state` and 10 `tt_*` tables, four RPC functions, and 0 rows in business_state until sign-in.
5. Configure `SUPABASE_URL` and `SUPABASE_KEY` near line 201 in the supplied `index.html` (use the same project's publishable/anon key; NEVER use service_role or secret key).
6. Upload V2 files to your ALREADY CONFIGURED GitHub Pages repository (`index.html`, `manifest.webmanifest`, `sw.js`, `offline.html`, `icons/`). Commit and reload, then sign in with your existing email account.
7. Create a staff member with status Active first; then add products, customers and stock. Checkout requires an active seller.
8. Test one small Cash sale, verify Orders, stock reduction, member total spent, loyalty points, receipt and Analytics. Test QR PAY manually, too. Do not use for real sales until checked.

Do not create a new Supabase project, delete any `auth.*` tables, or change authentication configuration.
The app is still based on `business_state` plus 10 normalized projection tables; the projections are NOT separate independently writable masters.

Caution: An installed older PWA may cache UI code. Refresh/reopen it after deployment; don't transact through the outdated app while setting up.
