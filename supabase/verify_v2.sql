-- Read-only checks to run in Supabase SQL Editor after running upgrade_v2.sql.
-- Every existing owner should have the SAME counts in business_state and tt_* projections.
select
 s.user_id, s.version,
 jsonb_array_length(coalesce(s.payload->'products','[]'::jsonb)) as old_products,
 (select count(*) from public.tt_products p where p.user_id=s.user_id) as new_products,
 jsonb_array_length(coalesce(s.payload->'orders','[]'::jsonb)) as old_orders,
 (select count(*) from public.tt_orders o where o.user_id=s.user_id) as new_orders,
 jsonb_array_length(coalesce(s.payload->'customers','[]'::jsonb)) as old_customers,
 (select count(*) from public.tt_customers c where c.user_id=s.user_id) as new_customers,
 jsonb_array_length(coalesce(s.payload->'staff','[]'::jsonb)) as old_staff,
 (select count(*) from public.tt_staff t where t.user_id=s.user_id) as new_staff
from public.business_state s
order by s.user_id;

-- Confirm core functions exist (no data modifications):
select p.proname as function_name
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('tt_checkout','tt_void_sale','tt_save_state_v2','tt_project_on_state_change')
order by p.proname;
