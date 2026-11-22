# Two Tales Business Admin V3 — Gifts & Vouchers

This is an **additive upgrade** for the existing V2 GitHub Pages / Supabase / PWA app.

**Start with [DEPLOY_V3.md](DEPLOY_V3.md).** It covers backups, V3 SQL migration, verification, GitHub changes, PWA refresh, security and acceptance tests.

- Run **only** `supabase/upgrade_v3_gifts_vouchers.sql` to migrate V2 to V3. Do not reset your current database.
- Run `supabase/verify_v3.sql` after the migration.
- Add your existing *public* Supabase project URL and publishable/anon key in `index.html` before upload.
- This ZIP intentionally contains **no live customer data**, private keys or Supabase credentials.

### Contents

| File | Purpose |
|---|---|
| `index.html` | Complete upgraded single-file app, including Gifts and Vouchers UI |
| `sw.js`, `manifest.webmanifest`, `offline.html`, `icons/` | PWA assets |
| `.gitignore` | Prevents accidental Git tracking of common secrets and exported backups |
| `.env.example` | Documentation placeholder, NOT loaded by the browser |
| `supabase/upgrade_v3_gifts_vouchers.sql` | Additive database changes and server-side transactions |
| `supabase/verify_v3.sql` | Read-only database checks |
| `supabase/backup_before_v3.sql` | Read-only snapshot inspection |
| `DEPLOY_V3.md` | Step-by-step instructions and testing checklist |

**Production limitations:** Server-side redemption and voucher checkout are atomic and version-checked, but we could not execute the SQL on your actual Supabase project. Test before accepting real payments. Your current V2 JSON snapshot and authenticated-admin trust model remain; this is not a granular multi-staff permission solution.
