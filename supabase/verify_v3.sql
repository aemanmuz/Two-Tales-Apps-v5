-- READ ONLY: run this after upgrade_v3_gifts_vouchers.sql
SELECT t.table_name
FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_name IN (
 'business_state','tt_gifts','tt_gift_variants','tt_gift_redemptions','tt_vouchers')
ORDER BY t.table_name;

SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('tt_checkout','tt_redeem_gift','tt_save_state_v2','tt_project_rewards_v3')
ORDER BY p.proname;

SELECT user_id,version,
 jsonb_array_length(coalesce(payload->'products','[]'::jsonb)) as products,
 jsonb_array_length(coalesce(payload->'orders','[]'::jsonb)) as orders,
 jsonb_array_length(coalesce(payload->'customers','[]'::jsonb)) as customers,
 jsonb_array_length(coalesce(payload->'gifts','[]'::jsonb)) as gifts,
 jsonb_array_length(coalesce(payload->'giftRedemptions','[]'::jsonb)) as gift_redemptions,
 jsonb_array_length(coalesce(payload->'vouchers','[]'::jsonb)) as vouchers
FROM public.business_state;

SELECT 'gift_catalog' AS entity, count(*) AS records FROM public.tt_gifts
UNION ALL SELECT 'gift_variants',count(*) FROM public.tt_gift_variants
UNION ALL SELECT 'gift_redemptions',count(*) FROM public.tt_gift_redemptions
UNION ALL SELECT 'vouchers',count(*) FROM public.tt_vouchers;
