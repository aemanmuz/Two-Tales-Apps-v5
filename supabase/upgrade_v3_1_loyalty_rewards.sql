-- TWO TALES V3.1 - MEMBER LOYALTY, GIFTS & POINTS VOUCHERS
-- Apply ONLY to an existing V3 Supabase installation. NO TRUNCATE, DROP TABLE, RESET or auth changes.
-- First: export a verified backup of public.business_state (payload + version), and schedule maintenance.
-- This updates functions and adds a read-only claim projection. The canonical state stays in business_state.
-- Current purchase rate: completed member POS orders earn floor(RM paid); previous order awards remain unchanged.
-- Historic POS points-as-money redemption remains in past sales records but is prohibited for new sales.
BEGIN;

CREATE TABLE IF NOT EXISTS public.tt_voucher_claims (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_id text NOT NULL, voucher_id text NOT NULL, voucher_code text,
 customer_id text NOT NULL, points integer NOT NULL CHECK(points>0),
 status text NOT NULL CHECK(status IN ('Claimed','Used','Cancelled')),
 used_order_id text, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,request_id)
);
ALTER TABLE public.tt_voucher_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tt_claims_read_owner_v3_1 ON public.tt_voucher_claims;
CREATE POLICY tt_claims_read_owner_v3_1 ON public.tt_voucher_claims
 FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
GRANT SELECT ON public.tt_voucher_claims TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.tt_voucher_claims FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.tt_project_claims_v3_1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r jsonb;
BEGIN
 DELETE FROM public.tt_voucher_claims WHERE user_id=NEW.user_id;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(coalesce(NEW.payload->'voucherClaims','[]'::jsonb)) x LOOP
   INSERT INTO public.tt_voucher_claims(user_id,request_id,voucher_id,voucher_code,customer_id,points,status,used_order_id,created_at)
   VALUES(NEW.user_id,r->>'requestId',r->>'voucherId',r->>'voucherCode',r->>'customerId',
          (r->>'points')::integer,coalesce(r->>'status','Claimed'),nullif(r->>'usedOrderId',''),
          coalesce(nullif(r->>'createdAt','')::timestamptz,pg_catalog.now()));
 END LOOP;
 RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.tt_project_claims_v3_1() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS tt_claims_projection_v3_1 ON public.business_state;
CREATE TRIGGER tt_claims_projection_v3_1 AFTER INSERT OR UPDATE OF payload ON public.business_state
 FOR EACH ROW EXECUTE FUNCTION public.tt_project_claims_v3_1();

-- Keep read-only V2 order / ledger projections consistent with explicit per-order award.
create or replace function public.tt_project_business_state(p_user uuid, p jsonb)
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  -- Child tables first, then parent tables; entire rewrite is within the same SQL transaction.
  delete from public.tt_loyalty_ledger where user_id=p_user;
  delete from public.tt_payments where user_id=p_user;
  delete from public.tt_order_items where user_id=p_user;
  delete from public.tt_orders where user_id=p_user;
  delete from public.tt_variants where user_id=p_user;
  delete from public.tt_products where user_id=p_user;
  delete from public.tt_customers where user_id=p_user;
  delete from public.tt_staff where user_id=p_user;
  delete from public.tt_inventory where user_id=p_user;
  delete from public.tt_cash_entries where user_id=p_user;

  insert into public.tt_products(user_id,legacy_id,name,price,cost,stock)
  select p_user,x->>'id',coalesce(x->>'name',''),coalesce((x->>'price')::numeric,0),
         coalesce((x->>'cost')::numeric,0),coalesce((x->>'stock')::integer,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'products','[]'::jsonb)) x where x->>'id' is not null;
  insert into public.tt_variants(user_id,product_id,legacy_id,name,price,stock)
  select p_user,x->>'id',v->>'id',coalesce(v->>'name',''),
         coalesce((v->>'price')::numeric,0),coalesce((v->>'stock')::integer,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'products','[]'::jsonb)) x
  cross join lateral pg_catalog.jsonb_array_elements(case when pg_catalog.jsonb_typeof(x->'variants')='array' then x->'variants' else '[]'::jsonb end) v
  where x->>'id' is not null and v->>'id' is not null;
  insert into public.tt_customers(user_id,legacy_id,name,phone,since,notes,opening_spent,opening_points)
  select p_user,x->>'id',coalesce(x->>'name',''),x->>'phone',nullif(x->>'since','')::date,x->>'notes',
         coalesce((x->>'spent')::numeric,0),coalesce((x->>'pointsOpening')::integer,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'customers','[]'::jsonb)) x where x->>'id' is not null;
  insert into public.tt_staff(user_id,legacy_id,name,role,status,phone,since)
  select p_user,x->>'id',coalesce(x->>'name',''),x->>'role',x->>'status',x->>'phone',nullif(x->>'since','')::date
  from pg_catalog.jsonb_array_elements(coalesce(p->'staff','[]'::jsonb)) x where x->>'id' is not null;
  insert into public.tt_orders(user_id,legacy_id,order_no,order_date,due_date,customer_id,customer_name,seller_id,seller_name,status,payment,subtotal,discount,points_redeemed,points_earned,total,paid,sale_request_id,notes)
  select p_user,x->>'id',coalesce((x->>'no')::bigint,0),nullif(x->>'date','')::date,nullif(x->>'due','')::date,
         x->>'customerId',coalesce(x->>'customer','Walk-in'),x->>'sellerId',x->>'sellerName',x->>'status',x->>'payment',
         coalesce((x->>'subtotal')::numeric,(x->>'total')::numeric,0),coalesce((x->>'discount')::numeric,0),
         coalesce((x->>'redeemedPoints')::integer,0),
         case when x->>'status'='Completed' and x->>'loyaltyEligible'='true' and nullif(x->>'customerId','') is not null
              then coalesce((x->>'pointsEarned')::integer,pg_catalog.floor(coalesce((x->>'paid')::numeric,0) / 10)::integer) else 0 end,
         coalesce((x->>'total')::numeric,0),coalesce((x->>'paid')::numeric,0),x->>'requestId',x->>'notes'
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x where x->>'id' is not null;
  insert into public.tt_order_items(user_id,order_id,line_no,product_id,variant_id,item_name,qty,unit_price,unit_cost)
  select p_user,x->>'id',j.ord::int,xitem->>'productId',xitem->>'variantId',coalesce(xitem->>'name',''),
    coalesce((xitem->>'qty')::numeric,0),coalesce((xitem->>'price')::numeric,0),coalesce((xitem->>'cost')::numeric,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x
  cross join lateral pg_catalog.jsonb_array_elements(case when pg_catalog.jsonb_typeof(x->'items')='array' then x->'items' else '[]'::jsonb end) with ordinality as j(xitem,ord)
  where x->>'id' is not null;
  insert into public.tt_payments(user_id,order_id,method,amount)
  select p_user,x->>'id',coalesce(x->>'payment','Cash'),coalesce((x->>'paid')::numeric,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x where x->>'id' is not null and coalesce((x->>'paid')::numeric,0)>0;
  insert into public.tt_loyalty_ledger(user_id,order_id,customer_id,event_type,points)
  select p_user,x->>'id',x->>'customerId','earn',coalesce((x->>'pointsEarned')::integer,pg_catalog.floor(coalesce((x->>'paid')::numeric,0)/10)::integer)
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x
  where x->>'status'='Completed' and x->>'loyaltyEligible'='true' and nullif(x->>'customerId','') is not null
        and coalesce((x->>'pointsEarned')::integer,pg_catalog.floor(coalesce((x->>'paid')::numeric,0)/10)::integer)>0;
  insert into public.tt_loyalty_ledger(user_id,order_id,customer_id,event_type,points)
  select p_user,x->>'id',x->>'customerId','redeem',-((x->>'redeemedPoints')::integer)
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x
  where x->>'status'='Completed' and nullif(x->>'customerId','') is not null and coalesce((x->>'redeemedPoints')::integer,0)>0;
  insert into public.tt_inventory(user_id,legacy_id,name,stock,reorder_level,unit_cost)
  select p_user,x->>'id',coalesce(x->>'name',''),coalesce((x->>'stock')::numeric,0),
         coalesce((x->>'reorder')::numeric,0),coalesce((x->>'cost')::numeric,0)
  from pg_catalog.jsonb_array_elements(coalesce(p->'inventory','[]'::jsonb)) x where x->>'id' is not null;
  insert into public.tt_cash_entries(user_id,legacy_id,entry_date,description,entry_type,amount,order_id)
  select p_user,x->>'id',nullif(x->>'date','')::date,x->>'description',x->>'type',
         coalesce((x->>'amount')::numeric,0),x->>'ref'
  from pg_catalog.jsonb_array_elements(coalesce(p->'cash','[]'::jsonb)) x where x->>'id' is not null;
end;
$fn$;

create or replace function public.tt_checkout(expected_version bigint, sale jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
 who uuid := (select auth.uid()); current_version bigint; state jsonb;
 products jsonb; orders jsonb; cash jsonb; customers jsonb; staff jsonb;
 existing jsonb; s jsonb; c jsonb; it jsonb; pr jsonb; vr jsonb; its jsonb:='[]'::jsonb;
 pid text; vid text; seller_id text; customer_id text; req_id text; key text; seen text[]:=array[]::text[];
 i int; j int; pi int; vi int; qty int; available int; redeem int:=0;
 unit_price numeric; unit_cost numeric; subtotal numeric:=0; discount numeric:=0; dval numeric; total numeric;
 paid numeric; cash_received numeric; change_due numeric:=0; order_no bigint:=0; new_id bigint;
 pay_method text; dkind text; note_text text; sale_date text;
 v_new_version bigint; result_order jsonb; display_name text; ord jsonb;
 voucher_claims jsonb; claim_record jsonb; claim_ref text; claim_index integer; claim_items jsonb;
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
 voucher_claims:=coalesce(state->'voucherClaims','[]'::jsonb);
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
 claim_ref:=nullif(sale->>'voucherClaimId','');
 if voucher_id is not null then
   select x into voucher from pg_catalog.jsonb_array_elements(vouchers) x where x->>'id'=voucher_id limit 1;
   if voucher is null or coalesce((voucher->>'active')::boolean,true)=false then raise exception 'Voucher is unavailable'; end if;
   -- Points-reward vouchers require a single-use claim already purchased by this member.
   if coalesce((voucher->>'pointsCost')::integer,0)>0 then
     if customer_id is null or claim_ref is null then raise exception 'This voucher must be claimed with points by a member first'; end if;
     select x into claim_record from pg_catalog.jsonb_array_elements(voucher_claims) x
      where x->>'requestId'=claim_ref and x->>'voucherId'=voucher_id and x->>'customerId'=customer_id
        and x->>'status'='Claimed' limit 1;
     if claim_record is null then raise exception 'Voucher claim is missing, assigned to another member, or already used'; end if;
   elsif claim_ref is not null then raise exception 'Claim reference must not be used with a regular voucher';
   end if;
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
 else
   if claim_ref is not null then raise exception 'Voucher claim requires a voucher'; end if;
 end if;
 -- Direct points-as-money at POS is intentionally disabled. Old historic redemptions remain in records.
 redeem:=coalesce((sale->>'redeemPoints')::integer,0);
 if redeem<>0 then raise exception 'Points cannot pay a POS bill; claim a gift or reward voucher instead'; end if;
 total:=pg_catalog.round(subtotal-discount-voucher_discount,2);
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
    'voucherClaimId',claim_ref,'pointsEarned',case when c is not null then pg_catalog.floor(paid)::integer else 0 end,
    'redeemedPoints',redeem,'loyaltyEligible',case when c is not null then true else false end,
    'total',total,'paid',paid,'tendered',cash_received,'change',change_due,
    'status','Completed','payment',pay_method,'notes',note_text,'requestId',req_id);
 orders:=orders || pg_catalog.jsonb_build_array(result_order);
 if claim_ref is not null then
   claim_index:=null;
   for i in 0..pg_catalog.jsonb_array_length(voucher_claims)-1 loop
     if voucher_claims->i->>'requestId'=claim_ref then claim_index:=i; exit; end if;
   end loop;
   if claim_index is null then raise exception 'Voucher claim missing'; end if;
   claim_record:=voucher_claims->claim_index;
   claim_record:=pg_catalog.jsonb_set(claim_record,'{status}','"Used"'::jsonb);
   claim_record:=pg_catalog.jsonb_set(claim_record,'{usedOrderId}',pg_catalog.to_jsonb(new_id::text));
   claim_record:=pg_catalog.jsonb_set(claim_record,'{usedAt}',pg_catalog.to_jsonb(pg_catalog.now()));
   voucher_claims:=pg_catalog.jsonb_set(voucher_claims,array[claim_index::text],claim_record);
 end if;
 if paid>0 then
   cash:=cash || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id',new_id,'date',sale_date,
      'description','Order #'||order_no||' ('||pay_method||')','type','in','amount',paid,'ref',new_id));
 end if;
 state:=pg_catalog.jsonb_set(state,'{products}',products);
 state:=pg_catalog.jsonb_set(state,'{orders}',orders);
 state:=pg_catalog.jsonb_set(state,'{cash}',cash);
 state:=pg_catalog.jsonb_set(state,'{voucherClaims}',voucher_claims);
 update public.business_state set payload=state,version=version+1 where user_id=who returning version into v_new_version;
 return pg_catalog.jsonb_build_object('version',v_new_version,'order',result_order,'alreadyProcessed',false);
end;
$fn$;

CREATE OR REPLACE FUNCTION public.tt_redeem_gift(expected_version bigint,claim jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 who uuid:=(SELECT auth.uid()); st jsonb; vers bigint; gifts jsonb; red jsonb; cust jsonb; orders jsonb;
 gift jsonb; variant jsonb; member jsonb; item jsonb; ord jsonb; rec jsonb; r jsonb; voucher_claims jsonb;
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
 cust:=coalesce(st->'customers','[]'::jsonb);gifts:=coalesce(st->'gifts','[]'::jsonb);orders:=coalesce(st->'orders','[]'::jsonb);voucher_claims:=coalesce(st->'voucherClaims','[]'::jsonb);
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
     IF coalesce((ord->>'loyaltyEligible')::boolean,false) THEN balance:=balance+coalesce((ord->>'pointsEarned')::int,pg_catalog.floor(coalesce((ord->>'paid')::numeric,0)/10)::int); END IF;
     balance:=balance-coalesce((ord->>'redeemedPoints')::int,0);
   END IF;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(red) x LOOP
   IF r->>'customerId'=customer_id AND coalesce(r->>'status','Completed')='Completed' THEN balance:=balance-coalesce((r->>'points')::int,0); END IF;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(voucher_claims) x LOOP
   IF r->>'customerId'=customer_id AND coalesce(r->>'status','Claimed')<>'Cancelled' THEN
     balance:=balance-coalesce((r->>'points')::int,0);
   END IF;
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

CREATE OR REPLACE FUNCTION public.tt_claim_voucher(expected_version bigint,claim jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 who uuid:=(SELECT auth.uid()); st jsonb; vers bigint; vouchers jsonb; claims jsonb; customers jsonb; orders jsonb; gifts jsonb;
 request_id text; customer_id text; voucher_id text; member jsonb; voucher jsonb; rec jsonb; ord jsonb; r jsonb;
 balance int; cost int; used_count int:=0; member_uses int:=0; reserved_count int:=0; reserved_member int:=0;
 claim_record jsonb; date_today date:=(pg_catalog.now() AT TIME ZONE 'Asia/Kuching')::date;
BEGIN
 IF who IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
 request_id:=pg_catalog.btrim(coalesce(claim->>'requestId',''));
 IF pg_catalog.length(request_id)<12 OR pg_catalog.length(request_id)>128 THEN RAISE EXCEPTION 'Invalid voucher claim reference'; END IF;
 SELECT payload,version INTO st,vers FROM public.business_state WHERE user_id=who FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Business data not found'; END IF;
 claims:=coalesce(st->'voucherClaims','[]'::jsonb);
 SELECT x INTO rec FROM pg_catalog.jsonb_array_elements(claims) x WHERE x->>'requestId'=request_id LIMIT 1;
 IF rec IS NOT NULL THEN RETURN pg_catalog.jsonb_build_object('version',vers,'claim',rec,'alreadyProcessed',true); END IF;
 IF expected_version IS DISTINCT FROM vers THEN RAISE EXCEPTION 'STALE_VERSION: refresh cloud and retry claim' USING errcode='40001'; END IF;
 customer_id:=nullif(claim->>'customerId','');voucher_id:=nullif(claim->>'voucherId','');
 IF customer_id IS NULL OR voucher_id IS NULL THEN RAISE EXCEPTION 'Select an existing member and a reward voucher'; END IF;
 customers:=coalesce(st->'customers','[]'::jsonb);vouchers:=coalesce(st->'vouchers','[]'::jsonb);
 orders:=coalesce(st->'orders','[]'::jsonb);gifts:=coalesce(st->'giftRedemptions','[]'::jsonb);
 SELECT x INTO member FROM pg_catalog.jsonb_array_elements(customers) x WHERE x->>'id'=customer_id LIMIT 1;
 IF member IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
 SELECT x INTO voucher FROM pg_catalog.jsonb_array_elements(vouchers) x WHERE x->>'id'=voucher_id LIMIT 1;
 IF voucher IS NULL OR coalesce((voucher->>'active')::boolean,true)=false THEN RAISE EXCEPTION 'Reward voucher unavailable'; END IF;
 cost:=coalesce((voucher->>'pointsCost')::integer,0);
 IF cost<1 THEN RAISE EXCEPTION 'Voucher has no points claim requirement'; END IF;
 IF coalesce((voucher->>'value')::numeric,0)<=0 OR (voucher->>'type' NOT IN ('fixed','percent')) OR
    (voucher->>'type'='percent' AND (voucher->>'value')::numeric>100) THEN
    RAISE EXCEPTION 'Voucher has an invalid discount value'; END IF;
 IF voucher->>'scope' NOT IN ('public','member') OR
   (voucher->>'scope'='member' AND voucher->>'customerId' IS DISTINCT FROM customer_id) THEN
   RAISE EXCEPTION 'Voucher not available to this member'; END IF;
 IF nullif(voucher->>'starts','') IS NOT NULL AND (voucher->>'starts')::date>date_today THEN RAISE EXCEPTION 'Voucher not yet active'; END IF;
 IF nullif(voucher->>'expires','') IS NOT NULL AND (voucher->>'expires')::date<date_today THEN RAISE EXCEPTION 'Voucher expired'; END IF;
 balance:=coalesce((member->>'pointsOpening')::integer,0);
 FOR ord IN SELECT x FROM pg_catalog.jsonb_array_elements(orders) x LOOP
   IF ord->>'customerId'=customer_id AND ord->>'status'='Completed' THEN
     IF coalesce((ord->>'loyaltyEligible')::boolean,false) THEN
       balance:=balance+coalesce((ord->>'pointsEarned')::integer,pg_catalog.floor(coalesce((ord->>'paid')::numeric,0)/10)::integer);
     END IF;
     balance:=balance-coalesce((ord->>'redeemedPoints')::integer,0);
   END IF;
   IF ord->>'status'='Completed' AND ord->>'voucherId'=voucher_id THEN
     used_count:=used_count+1;
     IF ord->>'customerId'=customer_id THEN member_uses:=member_uses+1; END IF;
   END IF;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(gifts) x LOOP
   IF r->>'customerId'=customer_id AND coalesce(r->>'status','Completed')='Completed' THEN balance:=balance-coalesce((r->>'points')::integer,0); END IF;
 END LOOP;
 FOR r IN SELECT x FROM pg_catalog.jsonb_array_elements(claims) x LOOP
   IF r->>'customerId'=customer_id AND coalesce(r->>'status','Claimed')<>'Cancelled' THEN balance:=balance-coalesce((r->>'points')::integer,0); END IF;
   IF r->>'voucherId'=voucher_id AND r->>'status'='Claimed' THEN
     reserved_count:=reserved_count+1;
     IF r->>'customerId'=customer_id THEN reserved_member:=reserved_member+1; END IF;
   END IF;
 END LOOP;
 IF balance<cost THEN RAISE EXCEPTION 'Insufficient loyalty points'; END IF;
 -- Do not allow stacking pending unredeemed copies of one voucher for the same member.
 IF reserved_member>0 THEN RAISE EXCEPTION 'Member already has an unused claim for this voucher'; END IF;
 IF coalesce((voucher->>'limit')::integer,0)>0 AND used_count+reserved_count >= (voucher->>'limit')::integer THEN
   RAISE EXCEPTION 'Voucher maximum claims and uses reached'; END IF;
 IF coalesce((voucher->>'perCustomerLimit')::integer,0)>0 AND member_uses+reserved_member >= (voucher->>'perCustomerLimit')::integer THEN
   RAISE EXCEPTION 'Member voucher usage limit reached'; END IF;
 claim_record:=pg_catalog.jsonb_build_object('requestId',request_id,'voucherId',voucher_id,'voucherCode',voucher->>'code',
  'customerId',customer_id,'points',cost,'status','Claimed','date',date_today,'createdAt',pg_catalog.now());
 claims:=claims||pg_catalog.jsonb_build_array(claim_record);
 st:=pg_catalog.jsonb_set(st,'{voucherClaims}',claims);
 UPDATE public.business_state SET payload=st,version=version+1 WHERE user_id=who RETURNING version INTO vers;
 RETURN pg_catalog.jsonb_build_object('version',vers,'claim',claim_record,'alreadyProcessed',false);
END;
$fn$;
REVOKE ALL ON FUNCTION public.tt_claim_voucher(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tt_claim_voucher(bigint,jsonb) TO authenticated;

create or replace function public.tt_void_sale(expected_version bigint, order_id text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
 who uuid:=(select auth.uid()); v bigint; st jsonb; os jsonb; prods jsonb; cas jsonb;
 ord jsonb; item jsonb; p jsonb; var jsonb; claims jsonb; claim_record jsonb; ix int; pi int; vi int; i int; j int;
 qty int; refund numeric; refund_id bigint; missing int:=0;
begin
 if who is null then raise exception 'Sign in required' using errcode='28000'; end if;
 select payload,version into st,v from public.business_state where user_id=who for update;
 if not found then raise exception 'Business data not found'; end if;
 os:=coalesce(st->'orders','[]'::jsonb);prods:=coalesce(st->'products','[]'::jsonb);
 cas:=coalesce(st->'cash','[]'::jsonb);claims:=coalesce(st->'voucherClaims','[]'::jsonb);
 ix:=null;
 for i in 0..pg_catalog.jsonb_array_length(os)-1 loop
   if os->i->>'id'=order_id then ix:=i;exit;end if;
 end loop;
 if ix is null then raise exception 'Order not found'; end if;
 ord:=os->ix;
 if ord->>'requestId' is null then raise exception 'Manual orders must be edited from Order Management'; end if;
 if ord->>'status'='Cancelled' then return pg_catalog.jsonb_build_object('version',v,'alreadyVoided',true,'order',ord); end if;
 if v is distinct from expected_version then raise exception 'STALE_VERSION: refresh cloud before voiding.' using errcode='40001'; end if;
 if ord->>'status'<>'Completed' then raise exception 'Only completed POS transactions can be voided'; end if;
 for item in select x from pg_catalog.jsonb_array_elements(coalesce(ord->'items','[]'::jsonb)) x loop
   pi:=null;
   for i in 0..pg_catalog.jsonb_array_length(prods)-1 loop
     if prods->i->>'id'=item->>'productId' then pi:=i;exit;end if;
   end loop;
   if pi is null then missing:=missing+1;continue;end if;
   p:=prods->pi;qty:=coalesce((item->>'qty')::integer,0);
   if item->>'variantId' is not null then
     vi:=null;
     for j in 0..pg_catalog.jsonb_array_length(coalesce(p->'variants','[]'::jsonb))-1 loop
       if p->'variants'->j->>'id'=item->>'variantId' then vi:=j;exit;end if;
     end loop;
     if vi is null then missing:=missing+1;continue;end if;
     var:=p->'variants'->vi;
     p:=pg_catalog.jsonb_set(p,array['variants',vi::text,'stock'],pg_catalog.to_jsonb(coalesce((var->>'stock')::int,0)+qty));
   else
     p:=pg_catalog.jsonb_set(p,'{stock}',pg_catalog.to_jsonb(coalesce((p->>'stock')::int,0)+qty));
   end if;
   prods:=pg_catalog.jsonb_set(prods,array[pi::text],p);
 end loop;
 refund:=coalesce((ord->>'paid')::numeric,0);
 -- Restore a single-use reward voucher claim when the associated sale is voided.
 if nullif(ord->>'voucherClaimId','') is not null then
   for i in 0..pg_catalog.jsonb_array_length(claims)-1 loop
     if claims->i->>'requestId'=ord->>'voucherClaimId' and claims->i->>'status'='Used' and claims->i->>'usedOrderId'=order_id then
       claim_record:=claims->i;
       claim_record:=pg_catalog.jsonb_set(claim_record,'{status}','"Claimed"'::jsonb);
       claim_record:=claim_record-'usedOrderId'-'usedAt';
       claims:=pg_catalog.jsonb_set(claims,array[i::text],claim_record);
       exit;
     end if;
   end loop;
 end if;
 ord:=pg_catalog.jsonb_set(ord,'{status}','"Cancelled"'::jsonb);
 ord:=pg_catalog.jsonb_set(ord,'{refundedAmount}',pg_catalog.to_jsonb(refund));
 ord:=pg_catalog.jsonb_set(ord,'{voidedAt}',pg_catalog.to_jsonb(pg_catalog.now()));
 os:=pg_catalog.jsonb_set(os,array[ix::text],ord);
 if refund>0 then
   refund_id:=-((ord->>'id')::bigint); -- stable, unique negative ID for an order's single refund
   cas:=cas || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id',refund_id,'date',ord->>'date',
     'description','Refund for voided order #'||(ord->>'no'),'type','out','amount',refund,'refundFor',ord->'id'));
 end if;
 st:=pg_catalog.jsonb_set(st,'{products}',prods);
 st:=pg_catalog.jsonb_set(st,'{orders}',os);
 st:=pg_catalog.jsonb_set(st,'{cash}',cas);
 st:=pg_catalog.jsonb_set(st,'{voucherClaims}',claims);
 update public.business_state set payload=st,version=version+1 where user_id=who returning version into v;
 return pg_catalog.jsonb_build_object('version',v,'order',ord,'missingStockItems',missing,'refundAmount',refund);
end;
$fn$;

-- Refresh existing voucher claim projections without modifying payloads or versions.
DO $sync$
DECLARE row_data record;
BEGIN
 FOR row_data IN SELECT user_id,payload FROM public.business_state LOOP
   DELETE FROM public.tt_voucher_claims WHERE user_id=row_data.user_id;
   INSERT INTO public.tt_voucher_claims(user_id,request_id,voucher_id,voucher_code,customer_id,points,status,used_order_id,created_at)
   SELECT row_data.user_id,x->>'requestId',x->>'voucherId',x->>'voucherCode',x->>'customerId',
     (x->>'points')::integer,coalesce(x->>'status','Claimed'),nullif(x->>'usedOrderId',''),
     coalesce(nullif(x->>'createdAt','')::timestamptz,pg_catalog.now())
   FROM pg_catalog.jsonb_array_elements(coalesce(row_data.payload->'voucherClaims','[]'::jsonb)) x;
 END LOOP;
END;
$sync$;
COMMIT;
