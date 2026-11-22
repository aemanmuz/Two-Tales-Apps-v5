-- TWO TALES V3 - ADDITIVE UPGRADE: GIFTS, POINTS REDEMPTION & VOUCHERS
-- IMPORTANT: BACK UP business_state FIRST. Does NOT delete existing records.
-- Run once using Supabase SQL Editor in the SAME project as the existing V2 app.
-- Preserves public.business_state, auth.users, all orders, customers and products.
-- Version requirement: V2 fresh-start schema with tt_checkout and tt_save_state_v2 already installed.
BEGIN;

-- Indexed read-only projections; business_state is the canonical snapshot in the current app.
CREATE TABLE IF NOT EXISTS public.tt_gifts (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 legacy_id text NOT NULL, name text NOT NULL, points integer NOT NULL CHECK(points>0),
 stock integer NOT NULL DEFAULT 0 CHECK(stock>=0), active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(user_id,legacy_id));
CREATE TABLE IF NOT EXISTS public.tt_gift_variants (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 gift_id text NOT NULL, legacy_id text NOT NULL, name text NOT NULL,
 points integer NOT NULL CHECK(points>0), stock integer NOT NULL DEFAULT 0 CHECK(stock>=0),
 PRIMARY KEY(user_id,gift_id,legacy_id),
 FOREIGN KEY(user_id,gift_id) REFERENCES public.tt_gifts(user_id,legacy_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS public.tt_gift_redemptions (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_id text NOT NULL, customer_id text NOT NULL, gift_id text NOT NULL,
 variant_id text, gift_name text NOT NULL, points integer NOT NULL CHECK(points>0),
 status text NOT NULL DEFAULT 'Completed', created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,request_id));
CREATE TABLE IF NOT EXISTS public.tt_vouchers (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 legacy_id text NOT NULL, code text NOT NULL, audience text NOT NULL,
 customer_id text, discount_type text NOT NULL, discount_value numeric(12,2) NOT NULL,
 start_date date, end_date date, max_uses integer NOT NULL DEFAULT 0,
 per_customer_limit integer NOT NULL DEFAULT 0, active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(user_id,legacy_id), UNIQUE(user_id,code));

ALTER TABLE public.tt_gifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tt_gift_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tt_gift_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tt_vouchers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tt_owner_select ON public.tt_gifts;
DROP POLICY IF EXISTS tt_owner_select ON public.tt_gift_variants;
DROP POLICY IF EXISTS tt_owner_select ON public.tt_gift_redemptions;
DROP POLICY IF EXISTS tt_owner_select ON public.tt_vouchers;
CREATE POLICY tt_owner_select ON public.tt_gifts FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY tt_owner_select ON public.tt_gift_variants FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY tt_owner_select ON public.tt_gift_redemptions FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY tt_owner_select ON public.tt_vouchers FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
GRANT SELECT ON public.tt_gifts,public.tt_gift_variants,public.tt_gift_redemptions,public.tt_vouchers TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.tt_gifts,public.tt_gift_variants,public.tt_gift_redemptions,public.tt_vouchers FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.tt_project_rewards_v3()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE g jsonb; v jsonb; r jsonb;
BEGIN
 DELETE FROM public.tt_gift_variants WHERE user_id=NEW.user_id;
 DELETE FROM public.tt_gifts WHERE user_id=NEW.user_id;
 DELETE FROM public.tt_gift_redemptions WHERE user_id=NEW.user_id;
 DELETE FROM public.tt_vouchers WHERE user_id=NEW.user_id;
 FOR g IN SELECT x FROM pg_catalog.jsonb_array_elements(coalesce(NEW.payload->'gifts','[]'::jsonb)) x LOOP
   INSERT INTO public.tt_gifts(user_id,legacy_id,name,points,stock,active)
   VALUES(NEW.user_id,g->>'id',coalesce(g->>'name',''),coalesce((g->>'points')::int,1),coalesce((g->>'stock')::int,0),coalesce((g->>'active')::boolean,true));
   FOR v IN SELECT x FROM pg_catalog.jsonb_array_elements(coalesce(g->'variants','[]'::jsonb)) x LOOP
     INSERT INTO public.tt_gift_variants(user_id,gift_id,legacy_id,name,points,stock)
     VALUES(NEW.user_id,g->>'id',v->>'id',coalesce(v->>'name',''),coalesce((v->>'points')::int,1),coalesce((v->>'stock')::int,0));
   END LOOP;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(coalesce(NEW.payload->'giftRedemptions','[]'::jsonb)) x LOOP
   INSERT INTO public.tt_gift_redemptions(user_id,request_id,customer_id,gift_id,variant_id,gift_name,points,status,created_at)
   VALUES(NEW.user_id,r->>'requestId',r->>'customerId',r->>'giftId',nullif(r->>'variantId',''),r->>'giftName',
    coalesce((r->>'points')::int,0),coalesce(r->>'status','Completed'),coalesce((r->>'createdAt')::timestamptz,now()));
 END LOOP;
 FOR v IN SELECT x FROM pg_catalog.jsonb_array_elements(coalesce(NEW.payload->'vouchers','[]'::jsonb)) x LOOP
   INSERT INTO public.tt_vouchers(user_id,legacy_id,code,audience,customer_id,discount_type,discount_value,start_date,end_date,max_uses,per_customer_limit,active)
   VALUES(NEW.user_id,v->>'id',upper(coalesce(v->>'code','')),coalesce(v->>'scope','public'),nullif(v->>'customerId',''),
    coalesce(v->>'type','fixed'),coalesce((v->>'value')::numeric,0),nullif(v->>'starts','')::date,nullif(v->>'expires','')::date,
    coalesce((v->>'limit')::int,0),coalesce((v->>'perCustomerLimit')::int,0),coalesce((v->>'active')::boolean,true));
 END LOOP;
 RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.tt_project_rewards_v3() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS tt_rewards_projection_v3 ON public.business_state;
CREATE TRIGGER tt_rewards_projection_v3 AFTER INSERT OR UPDATE OF payload ON public.business_state
FOR EACH ROW EXECUTE FUNCTION public.tt_project_rewards_v3();

-- Checkout uses the existing V2 row lock and transaction ID. New voucher checks are authoritative.
create or replace function public.tt_checkout(expected_version bigint, sale jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
 who uuid := (select auth.uid()); current_version bigint; state jsonb;
 products jsonb; orders jsonb; cash jsonb; customers jsonb; staff jsonb;
 existing jsonb; s jsonb; c jsonb; it jsonb; pr jsonb; vr jsonb; its jsonb:='[]'::jsonb;
 pid text; vid text; seller_id text; customer_id text; req_id text; key text; seen text[]:=array[]::text[];
 i int; j int; pi int; vi int; qty int; available int; points_balance int:=0; redeem int:=0;
 unit_price numeric; unit_cost numeric; subtotal numeric:=0; discount numeric:=0; dval numeric; total numeric;
 paid numeric; cash_received numeric; change_due numeric:=0; order_no bigint:=0; new_id bigint;
 pay_method text; dkind text; note_text text; sale_date text;
 v_new_version bigint; result_order jsonb; display_name text; ord jsonb;
 gift_redemptions jsonb; reward jsonb;
 vouchers jsonb; voucher jsonb; voucher_id text; voucher_code text; voucher_discount numeric:=0; voucher_uses int:=0; customer_uses int:=0; voucher_base numeric; 
begin
 if who is null then raise exception 'Please sign in' using errcode='28000'; end if;
 req_id := pg_catalog.btrim(coalesce(sale->>'requestId',''));
 if pg_catalog.length(req_id)<12 or pg_catalog.length(req_id)>128 then raise exception 'Invalid transaction reference'; end if;
 insert into public.business_state(user_id,payload,version)
 values(who,'{"products":[],"orders":[],"customers":[],"inventory":[],"cash":[],"staff":[]}'::jsonb,0)
 on conflict(user_id) do nothing;
 select payload,version into state,current_version from public.business_state where user_id=who for update;
 products:=coalesce(state->'products','[]'::jsonb);
 orders:=coalesce(state->'orders','[]'::jsonb);
 cash:=coalesce(state->'cash','[]'::jsonb);
 customers:=coalesce(state->'customers','[]'::jsonb);
 staff:=coalesce(state->'staff','[]'::jsonb);
 gift_redemptions:=coalesce(state->'giftRedemptions','[]'::jsonb);
 vouchers:=coalesce(state->'vouchers','[]'::jsonb);
 -- A network timeout followed by a retry must never sell or award points twice.
 select x into existing from pg_catalog.jsonb_array_elements(orders) x where x->>'requestId'=req_id limit 1;
 if existing is not null then return pg_catalog.jsonb_build_object('version',current_version,'order',existing,'alreadyProcessed',true); end if;
 if expected_version is distinct from current_version then
    raise exception 'STALE_VERSION: data changed on another device. Refresh and retry checkout.' using errcode='40001';
 end if;
 seller_id:=sale->>'sellerId'; customer_id:=nullif(sale->>'customerId','');
 select x into s from pg_catalog.jsonb_array_elements(staff) x where x->>'id'=seller_id and x->>'status'='Active' limit 1;
 if s is null then raise exception 'Choose an active sales staff member'; end if;
 if customer_id is not null then
    select x into c from pg_catalog.jsonb_array_elements(customers) x where x->>'id'=customer_id limit 1;
    if c is null then raise exception 'Selected customer no longer exists'; end if;
 end if;
 pay_method:=sale->>'payment';
 if pay_method not in ('Cash','QR PAY') then raise exception 'Invalid payment method'; end if;
 if pay_method='QR PAY' and coalesce((sale->>'qrConfirmed')::boolean,false) = false then
   raise exception 'Confirm receipt of QR payment before completing the sale'; end if;
 if pg_catalog.jsonb_typeof(sale->'items') <> 'array' or pg_catalog.jsonb_array_length(sale->'items')=0 then
    raise exception 'Cart cannot be empty'; end if;
 if pg_catalog.jsonb_array_length(sale->'items')>150 then raise exception 'Too many items'; end if;
 for it in select x from pg_catalog.jsonb_array_elements(sale->'items') x loop
   pid:=it->>'productId'; vid:=nullif(it->>'variantId','');
   if vid='null' then vid:=null; end if;
   key:=coalesce(pid,'') || ':' || coalesce(vid,'base');
   if key=any(seen) then raise exception 'Duplicate item in cart'; end if;
   seen:=pg_catalog.array_append(seen,key);
   qty:=(it->>'qty')::integer;
   if qty<1 or qty>999 then raise exception 'Invalid item quantity'; end if;
   pi:=null;
   for i in 0..pg_catalog.jsonb_array_length(products)-1 loop
      if products->i->>'id'=pid then pi:=i; exit; end if;
   end loop;
   if pi is null then raise exception 'Product no longer exists'; end if;
   pr:=products->pi; unit_cost:=coalesce((pr->>'cost')::numeric,0);
   if pg_catalog.jsonb_typeof(pr->'variants')='array' and pg_catalog.jsonb_array_length(pr->'variants')>0 then
      if vid is null then raise exception 'Choose a product variant'; end if;
      vi:=null;
      for j in 0..pg_catalog.jsonb_array_length(pr->'variants')-1 loop
         if pr->'variants'->j->>'id'=vid then vi:=j; exit; end if;
      end loop;
      if vi is null then raise exception 'Product variant no longer exists'; end if;
      vr:=pr->'variants'->vi;
      available:=coalesce((vr->>'stock')::integer,0);
      unit_price:=coalesce((vr->>'price')::numeric,0);
      display_name:=coalesce(pr->>'name','') || ' — ' || coalesce(vr->>'name','');
      if available<qty then raise exception 'Insufficient stock for %',display_name; end if;
      pr:=pg_catalog.jsonb_set(pr,array['variants',vi::text,'stock'],pg_catalog.to_jsonb(available-qty));
   else
      if vid is not null then raise exception 'Variant not available'; end if;
      available:=coalesce((pr->>'stock')::integer,0);
      unit_price:=coalesce((pr->>'price')::numeric,0);
      display_name:=coalesce(pr->>'name','');
      if available<qty then raise exception 'Insufficient stock for %',display_name; end if;
      pr:=pg_catalog.jsonb_set(pr,'{stock}',pg_catalog.to_jsonb(available-qty));
   end if;
   if unit_price<0 then raise exception 'Invalid product price'; end if;
   if pg_catalog.abs(unit_price - coalesce((it->>'price')::numeric,-1)) > 0.009 then
      raise exception 'Price changed for %. Refresh the cart before checkout.',display_name;
   end if;
   products:=pg_catalog.jsonb_set(products,array[pi::text],pr);
   subtotal:=subtotal+(qty*unit_price);
   its:=its || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'productId',(it->'productId'),'variantId',case when vid is null then 'null'::jsonb else it->'variantId' end,
      'name',display_name,'qty',qty,'price',unit_price,'cost',unit_cost,
      'key',key,'id',(it->'productId')));
 end loop;
 subtotal:=pg_catalog.round(subtotal,2);
 dkind:=coalesce(sale->>'discountType','fixed'); dval:=coalesce((sale->>'discountValue')::numeric,0);
 if dval<0 or dval>1000000 then raise exception 'Invalid discount'; end if;
 if dkind='percent' then
    if dval>100 then raise exception 'Percentage discount cannot exceed 100'; end if;
    discount:=pg_catalog.round(subtotal*dval/100,2);
 elsif dkind='fixed' then discount:=pg_catalog.round(dval,2);
 else raise exception 'Invalid discount type'; end if;
 if discount>subtotal then raise exception 'Discount exceeds subtotal'; end if;
 voucher_id:=nullif(sale->>'voucherId','');
 if voucher_id is not null then
   select x into voucher from pg_catalog.jsonb_array_elements(vouchers) x where x->>'id'=voucher_id limit 1;
   if voucher is null or coalesce((voucher->>'active')::boolean,true)=false then raise exception 'Voucher is unavailable'; end if;
   if voucher->>'scope'='member' and (c is null or voucher->>'customerId'<>customer_id) then raise exception 'This voucher belongs to another customer'; end if;
   if voucher->>'scope' not in ('public','member') then raise exception 'Invalid voucher audience'; end if;
   if nullif(voucher->>'starts','') is not null and (voucher->>'starts')::date > (sale->>'date')::date then raise exception 'Voucher is not active yet'; end if;
   if nullif(voucher->>'expires','') is not null and (voucher->>'expires')::date < (sale->>'date')::date then raise exception 'Voucher has expired'; end if;
   select count(*),count(*) filter (where x->>'customerId'=customer_id) into voucher_uses,customer_uses
   from pg_catalog.jsonb_array_elements(orders) x
   where x->>'voucherId'=voucher_id and x->>'status'='Completed';
   if coalesce((voucher->>'limit')::int,0)>0 and voucher_uses>=((voucher->>'limit')::int) then raise exception 'Voucher usage limit reached'; end if;
   if coalesce((voucher->>'perCustomerLimit')::int,0)>0 and customer_id is not null and customer_uses>=((voucher->>'perCustomerLimit')::int) then raise exception 'Voucher customer usage limit reached'; end if;
   voucher_base:=subtotal-discount;
   if coalesce((voucher->>'value')::numeric,0)<=0 then raise exception 'Invalid voucher value'; end if;
   if voucher->>'type'='percent' then
     if (voucher->>'value')::numeric>100 then raise exception 'Invalid voucher percentage'; end if;
     voucher_discount:=pg_catalog.round(voucher_base*(voucher->>'value')::numeric/100,2);
   elsif voucher->>'type'='fixed' then
     voucher_discount:=pg_catalog.least(voucher_base,(voucher->>'value')::numeric);
   else raise exception 'Invalid voucher discount type'; end if;
   voucher_code:=voucher->>'code';
 end if;
 redeem:=coalesce((sale->>'redeemPoints')::integer,0);
 if redeem<0 then raise exception 'Points cannot be negative'; end if;
 if redeem>0 then
   if c is null then raise exception 'Select a member to redeem points'; end if;
   points_balance:=coalesce((c->>'pointsOpening')::integer,0);
   for ord in select x from pg_catalog.jsonb_array_elements(orders) x loop
      if ord->>'customerId'=customer_id and ord->>'status'='Completed' then
         if ord->>'loyaltyEligible'='true' then
            points_balance:=points_balance + pg_catalog.floor(coalesce((ord->>'paid')::numeric,0)/10)::integer;
         end if;
         points_balance:=points_balance - coalesce((ord->>'redeemedPoints')::integer,0);
      end if;
   end loop;
   for reward in select x from pg_catalog.jsonb_array_elements(gift_redemptions) x loop
      if reward->>'customerId'=customer_id and coalesce(reward->>'status','Completed')='Completed' then
         points_balance:=points_balance-coalesce((reward->>'points')::integer,0);
      end if;
   end loop;
   if redeem>points_balance then raise exception 'Insufficient customer loyalty points'; end if;
   if redeem::numeric/10>subtotal-discount-voucher_discount then raise exception 'Points redemption exceeds payable amount'; end if;
 end if;
 total:=pg_catalog.round(subtotal-discount-voucher_discount-redeem::numeric/10,2);
 cash_received:=coalesce((sale->>'cashReceived')::numeric,0);
 if pay_method='Cash' then
   if cash_received<total then raise exception 'Cash received is less than amount due'; end if;
   change_due:=pg_catalog.round(cash_received-total,2);
 else
   cash_received:=0; change_due:=0;
 end if;
 paid:=total;
 for ord in select x from pg_catalog.jsonb_array_elements(orders) x loop
    order_no:=greatest(order_no,coalesce((ord->>'no')::bigint,0));
 end loop;
 order_no:=order_no+1;
 new_id:=coalesce((sale->>'orderId')::bigint,0);
 if new_id<1 then raise exception 'Invalid order reference'; end if;
 if exists(select 1 from pg_catalog.jsonb_array_elements(orders) x where x->>'id'=new_id::text) then raise exception 'Order ID already exists'; end if;
 note_text:=pg_catalog.left(coalesce(sale->>'notes',''),1000);
 -- Dates use the client's local business date; never silently force the UTC date.
 sale_date:=sale->>'date';
 if sale_date is null or sale_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Invalid sale date'; end if;
 perform sale_date::date;
 result_order:=pg_catalog.jsonb_build_object('id',new_id,'no',order_no,'date',sale_date,'due',sale_date,
    'createdAt',pg_catalog.now(),'customer',coalesce(c->>'name','Walk-in'),'customerId',
    case when customer_id is null then 'null'::jsonb else pg_catalog.to_jsonb((c->'id')) end,
    'sellerId',s->'id','sellerName',s->>'name','items',its,'subtotal',subtotal,
    'discountType',dkind,'discountValue',dval,'discount',discount,
    'voucherId',voucher_id,'voucherCode',voucher_code,'voucherDiscount',voucher_discount,
    'redeemedPoints',redeem,'loyaltyEligible',case when c is not null then true else false end,
    'total',total,'paid',paid,'tendered',cash_received,'change',change_due,
    'status','Completed','payment',pay_method,'notes',note_text,'requestId',req_id);
 orders:=orders || pg_catalog.jsonb_build_array(result_order);
 if paid>0 then
   cash:=cash || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id',new_id,'date',sale_date,
      'description','Order #'||order_no||' ('||pay_method||')','type','in','amount',paid,'ref',new_id));
 end if;
 state:=pg_catalog.jsonb_set(state,'{products}',products);
 state:=pg_catalog.jsonb_set(state,'{orders}',orders);
 state:=pg_catalog.jsonb_set(state,'{cash}',cash);
 update public.business_state set payload=state,version=version+1 where user_id=who returning version into v_new_version;
 return pg_catalog.jsonb_build_object('version',v_new_version,'order',result_order,'alreadyProcessed',false);
end;
$fn$;
REVOKE ALL ON FUNCTION public.tt_checkout(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tt_checkout(bigint,jsonb) TO authenticated;

-- Atomic point redemption + stock deduction + deduplication, tied to the same account.
CREATE OR REPLACE FUNCTION public.tt_redeem_gift(expected_version bigint,claim jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 who uuid:=(SELECT auth.uid()); st jsonb; vers bigint; gifts jsonb; red jsonb; cust jsonb; orders jsonb;
 gift jsonb; variant jsonb; member jsonb; item jsonb; ord jsonb; rec jsonb; r jsonb;
 request_id text; customer_id text; gift_id text; variant_id text; idx int; jdx int;
 i int; j int; pts int; balance int; available int; label text; redemption_out jsonb;
BEGIN
 IF who IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
 request_id:=pg_catalog.btrim(coalesce(claim->>'requestId',''));
 IF pg_catalog.length(request_id)<12 OR pg_catalog.length(request_id)>128 THEN RAISE EXCEPTION 'Invalid request reference'; END IF;
 SELECT payload,version INTO st,vers FROM public.business_state WHERE user_id=who FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Business state is missing'; END IF;
 red:=coalesce(st->'giftRedemptions','[]'::jsonb);
 SELECT x INTO rec FROM pg_catalog.jsonb_array_elements(red) x WHERE x->>'requestId'=request_id LIMIT 1;
 IF rec IS NOT NULL THEN RETURN pg_catalog.jsonb_build_object('version',vers,'redemption',rec,'alreadyProcessed',true); END IF;
 IF expected_version IS DISTINCT FROM vers THEN RAISE EXCEPTION 'STALE_VERSION: refresh cloud and try again' USING errcode='40001'; END IF;
 customer_id:=claim->>'customerId';gift_id:=claim->>'giftId';variant_id:=nullif(claim->>'variantId','');
 cust:=coalesce(st->'customers','[]'::jsonb);gifts:=coalesce(st->'gifts','[]'::jsonb);orders:=coalesce(st->'orders','[]'::jsonb);
 SELECT x INTO member FROM pg_catalog.jsonb_array_elements(cust) x WHERE x->>'id'=customer_id LIMIT 1;
 IF member IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
 idx:=null;
 FOR i IN 0..pg_catalog.jsonb_array_length(gifts)-1 LOOP IF gifts->i->>'id'=gift_id THEN idx:=i; EXIT; END IF; END LOOP;
 IF idx IS NULL THEN RAISE EXCEPTION 'Gift not found'; END IF;
 gift:=gifts->idx;
 IF coalesce((gift->>'active')::boolean,true)=false THEN RAISE EXCEPTION 'Gift is disabled'; END IF;
 IF pg_catalog.jsonb_array_length(coalesce(gift->'variants','[]'::jsonb))>0 THEN
   IF variant_id IS NULL THEN RAISE EXCEPTION 'Select gift variant'; END IF;
   jdx:=null;
   FOR j IN 0..pg_catalog.jsonb_array_length(gift->'variants')-1 LOOP IF gift->'variants'->j->>'id'=variant_id THEN jdx:=j; EXIT; END IF; END LOOP;
   IF jdx IS NULL THEN RAISE EXCEPTION 'Variant not found'; END IF;
   variant:=gift->'variants'->jdx;pts:=(variant->>'points')::int; available:=(variant->>'stock')::int;label:=variant->>'name';
 ELSE
   IF variant_id IS NOT NULL THEN RAISE EXCEPTION 'Gift has no variants'; END IF;
   pts:=(gift->>'points')::int;available:=(gift->>'stock')::int;label:=null;
 END IF;
 IF pts<1 OR available<1 THEN RAISE EXCEPTION 'Gift is out of stock or has invalid point cost'; END IF;
 balance:=coalesce((member->>'pointsOpening')::int,0);
 FOR ord IN SELECT x FROM pg_catalog.jsonb_array_elements(orders) x LOOP
   IF ord->>'customerId'=customer_id AND ord->>'status'='Completed' THEN
     IF coalesce((ord->>'loyaltyEligible')::boolean,false) THEN balance:=balance+pg_catalog.floor(coalesce((ord->>'paid')::numeric,0)/10)::int; END IF;
     balance:=balance-coalesce((ord->>'redeemedPoints')::int,0);
   END IF;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(red) x LOOP
   IF r->>'customerId'=customer_id AND coalesce(r->>'status','Completed')='Completed' THEN balance:=balance-coalesce((r->>'points')::int,0); END IF;
 END LOOP;
 IF balance<pts THEN RAISE EXCEPTION 'Insufficient loyalty points'; END IF;
 IF variant_id IS NULL THEN gift:=pg_catalog.jsonb_set(gift,'{stock}',pg_catalog.to_jsonb(available-1));
 ELSE gift:=pg_catalog.jsonb_set(gift,ARRAY['variants',jdx::text,'stock'],pg_catalog.to_jsonb(available-1)); END IF;
 gifts:=pg_catalog.jsonb_set(gifts,ARRAY[idx::text],gift);
 redemption_out:=pg_catalog.jsonb_build_object('requestId',request_id,'giftId',gift_id,'variantId',variant_id,'giftName',gift->>'name',
 'variantName',label,'customerId',customer_id,'points',pts,'status','Completed','date',coalesce(claim->>'date',current_date::text),'createdAt',pg_catalog.now());
 red:=red||pg_catalog.jsonb_build_array(redemption_out);
 st:=pg_catalog.jsonb_set(st,'{gifts}',gifts);st:=pg_catalog.jsonb_set(st,'{giftRedemptions}',red);
 UPDATE public.business_state SET payload=st,version=version+1 WHERE user_id=who RETURNING version INTO vers;
 RETURN pg_catalog.jsonb_build_object('version',vers,'redemption',redemption_out,'alreadyProcessed',false);
END;
$fn$;
REVOKE ALL ON FUNCTION public.tt_redeem_gift(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tt_redeem_gift(bigint,jsonb) TO authenticated;

-- Backfill projections for previously saved users without changing their business payloads.
DO $backfill$
DECLARE r record;
BEGIN
 FOR r IN SELECT user_id,payload FROM public.business_state LOOP
   -- invoke via a no-op version-preserving payload update to trigger projection
   UPDATE public.business_state SET payload=payload WHERE user_id=r.user_id;
 END LOOP;
END;
$backfill$;
COMMIT;
