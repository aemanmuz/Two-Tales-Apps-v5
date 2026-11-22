# Two Tales V3 — Customer duplicate ID hotfix

## Why cloud saves fail
The V2/V3 `tt_save_state_v2` function updates `business_state`. A trigger projects the entire JSON snapshot into structured tables including `tt_customers(user_id,legacy_id)` with a unique primary key. Duplicate `id` values in the JSON customers list abort the SQL transaction. The old frontend `uid()` used `Date.now()*1000 + random(0..999)`, which could collide during bulk CSV imports.

## Before doing anything
1. In your currently open broken V3 tab, download **Backup data** and **Export unsaved recovery** (if available). DO NOT reload until you've saved the JSON files.
2. Don't repeatedly try to save and don't run fresh-start SQL; don't drop/disable primary keys or triggers.
3. Run `supabase/diagnose_duplicate_customer_ids.sql` in Supabase SQL Editor (read-only).
4. If the query returns zero rows but the browser fails, the duplicate is likely only in the UNSAVED browser snapshot. Compare the exported backup JSON with the cloud JSON.
5. If duplicates have orders/redemptions referencing them, do not automatically merge or renumber them. You must map history to the correct customer record first.

## Deploy the frontend prevention update
`index.html` now uses a monotonic collision-checking numeric ID generator and detects duplicate customer IDs before sending a save request. This reduces future collisions; **it does NOT repair already duplicated customer IDs in an unsaved backup**.

After recovering existing data, copy updated website files to your existing GitHub Pages repo; commit and hard refresh/refresh the PWA cache. There is no SQL migration to apply for this ID generator change.

## What to share for a safe repair
Send the diagnostic query output, and optionally the unsaved JSON backup **only if comfortable sharing customer data**. Redact names/phone numbers if sharing a screenshot; duplicate ID counts and references are enough for an initial diagnosis.
