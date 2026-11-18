-- Run in a NEW SQL Editor query AFTER fresh_start_v2.sql succeeds.
-- Expect ten tt_* table names and the four V2 functions.
select table_name from information_schema.tables
where table_schema='public' and table_name in
('business_state','tt_products','tt_variants','tt_customers','tt_staff','tt_orders','tt_order_items','tt_payments','tt_loyalty_ledger','tt_inventory','tt_cash_entries')
order by table_name;

select routine_name from information_schema.routines
where routine_schema='public' and routine_name in
('tt_checkout','tt_void_sale','tt_save_state_v2','tt_project_on_state_change')
order by routine_name;

-- Fresh-start rows should be 0 (until the website is used).
select count(*) as business_accounts_initialized from public.business_state;
