-- Read-only verification of V3.1 Supabase routines and member voucher claim projection.
-- Run after upgrade_v3_1_loyalty_rewards.sql; does not read personal customer details.
SELECT routine_name FROM information_schema.routines
 WHERE routine_schema = 'public' AND routine_name IN
  ('tt_save_state_v2','tt_checkout','tt_void_sale','tt_redeem_gift','tt_claim_voucher','tt_project_business_state','tt_project_claims_v3_1')
 ORDER BY routine_name;

SELECT COUNT(*) AS claimed_rewards_total,
       COUNT(*) FILTER (WHERE status='Claimed') AS ready_to_use,
       COUNT(*) FILTER (WHERE status='Used') AS used_claims
FROM public.tt_voucher_claims;

SELECT COUNT(*) AS orders_with_explicit_points,
       COALESCE(SUM(points_earned),0) AS points_earned_in_projection
FROM public.tt_orders WHERE status='Completed' AND points_earned>0;

-- Inspect only table and trigger metadata:
SELECT trigger_name,event_manipulation,event_object_table
 FROM information_schema.triggers
 WHERE event_object_schema='public' AND event_object_table='business_state'
   AND trigger_name='tt_claims_projection_v3_1';
