-- TWO TALES BUSINESS ADMIN V2 - FRESH START (18 NOV 2026)
-- DESTRUCTIVE FOR TWO TALES BUSINESS DATA ONLY.
 -- Deletes ALL stored Two Tales business products, customers, orders, stock,
 -- staff, cash entries and legacy payloads. It DOES NOT touch auth.users,
 -- authentication providers, your emails, credentials, or GitHub Pages files.
 -- Run the ENTIRE SQL in the EXISTING Supabase project SQL Editor, no selection.
 -- If any statement fails, the transaction rolls back.

begin;

-- Establish the table even if an earlier migration only partially ran.
create table if not exists public.business_state (
 user_id uuid primary key references auth.users(id) on delete cascade,
 payload jsonb not null default '{"products":[],"orders":[],"customers":[],"inventory":[],"cash":[],"staff":[]}'::jsonb,
 version bigint not null default 0
);
alter table public.business_state add column if not exists version bigint not null default 0;

-- Stop old sync trigger before clearing records.
drop trigger if exists tt_projection_sync_v2 on public.business_state;

-- Reset the legacy snapshot. Authentication users remain intact.
delete from public.business_state;

-- Remove partially-created V2 projection tables, children before parents.
drop table if exists public.tt_loyalty_ledger;
drop table if exists public.tt_payments;
drop table if exists public.tt_order_items;
drop table if exists public.tt_variants;
drop table if exists public.tt_cash_entries;
drop table if exists public.tt_inventory;
drop table if exists public.tt_staff;
drop table if exists public.tt_orders;
drop table if exists public.tt_customers;
drop table if exists public.tt_products;

-- Recreate the exact schema and RPCs used by the V2 website.
create table if not exists public.business_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{"products":[],"orders":[],"customers":[],"inventory":[],"cash":[],"staff":[]}'::jsonb,
  version bigint not null default 0
);
alter table public.business_state enable row level security;
-- Use plain SQL rather than dollar-quoted DO blocks in the RLS section.
-- Only the policy with this exact name is replaced; existing policies remain unchanged.
drop policy if exists tt_owner_read_v2 on public.business_state;
create policy tt_owner_read_v2 on public.business_state
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.business_state to authenticated;

create table if not exists public.tt_products (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 name text not null, price numeric(12,2) not null default 0, cost numeric(12,2) not null default 0,
 stock integer not null default 0, primary key (user_id, legacy_id)
);
create table if not exists public.tt_variants (
 user_id uuid not null references auth.users(id) on delete cascade,
 product_id text not null, legacy_id text not null, name text not null,
 price numeric(12,2) not null default 0, stock integer not null default 0,
 primary key(user_id, product_id, legacy_id),
 foreign key(user_id,product_id) references public.tt_products(user_id,legacy_id) on delete cascade
);
create table if not exists public.tt_customers (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 name text not null, phone text, since date, notes text,
 opening_spent numeric(12,2) not null default 0, opening_points integer not null default 0,
 primary key(user_id,legacy_id)
);
create table if not exists public.tt_staff (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 name text not null, role text, status text, phone text, since date,
 primary key(user_id, legacy_id)
);
create table if not exists public.tt_orders (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 order_no bigint not null, order_date date, due_date date, customer_id text, customer_name text,
 seller_id text, seller_name text, status text, payment text,
 subtotal numeric(12,2) not null default 0, discount numeric(12,2) not null default 0,
 points_redeemed integer not null default 0, points_earned integer not null default 0,
 total numeric(12,2) not null default 0, paid numeric(12,2) not null default 0,
 sale_request_id text, notes text, primary key(user_id,legacy_id)
);
create table if not exists public.tt_order_items (
 user_id uuid not null references auth.users(id) on delete cascade, order_id text not null,
 line_no integer not null, product_id text, variant_id text,
 item_name text not null, qty numeric(12,2) not null, unit_price numeric(12,2) not null,
 unit_cost numeric(12,2) not null default 0,
 primary key(user_id,order_id,line_no),
 foreign key(user_id,order_id) references public.tt_orders(user_id,legacy_id) on delete cascade
);
create table if not exists public.tt_payments (
 user_id uuid not null references auth.users(id) on delete cascade, order_id text not null,
 method text not null, amount numeric(12,2) not null default 0,
 primary key(user_id,order_id),
 foreign key(user_id,order_id) references public.tt_orders(user_id,legacy_id) on delete cascade
);
create table if not exists public.tt_loyalty_ledger (
 user_id uuid not null references auth.users(id) on delete cascade, order_id text not null,
 customer_id text not null, event_type text not null check(event_type in ('earn','redeem')),
 points integer not null, primary key(user_id,order_id,event_type),
 foreign key(user_id,order_id) references public.tt_orders(user_id,legacy_id) on delete cascade
);
create table if not exists public.tt_inventory (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 name text not null, stock numeric(12,2), reorder_level numeric(12,2), unit_cost numeric(12,2),
 primary key(user_id,legacy_id)
);
create table if not exists public.tt_cash_entries (
 user_id uuid not null references auth.users(id) on delete cascade, legacy_id text not null,
 entry_date date, description text, entry_type text, amount numeric(12,2), order_id text,
 primary key(user_id,legacy_id)
);

-- Authenticated clients may query their own projections but never mutate them directly.
-- Explicit SQL avoids the unterminated-dollar-quote error when an editor
-- executes only part of a DO $policy$ statement. Safe to rerun.
alter table public.tt_products enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_products;
create policy tt_read_owner_v2 on public.tt_products
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_products to authenticated;
revoke insert, update, delete on public.tt_products from anon, authenticated;

alter table public.tt_variants enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_variants;
create policy tt_read_owner_v2 on public.tt_variants
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_variants to authenticated;
revoke insert, update, delete on public.tt_variants from anon, authenticated;

alter table public.tt_customers enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_customers;
create policy tt_read_owner_v2 on public.tt_customers
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_customers to authenticated;
revoke insert, update, delete on public.tt_customers from anon, authenticated;

alter table public.tt_staff enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_staff;
create policy tt_read_owner_v2 on public.tt_staff
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_staff to authenticated;
revoke insert, update, delete on public.tt_staff from anon, authenticated;

alter table public.tt_orders enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_orders;
create policy tt_read_owner_v2 on public.tt_orders
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_orders to authenticated;
revoke insert, update, delete on public.tt_orders from anon, authenticated;

alter table public.tt_order_items enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_order_items;
create policy tt_read_owner_v2 on public.tt_order_items
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_order_items to authenticated;
revoke insert, update, delete on public.tt_order_items from anon, authenticated;

alter table public.tt_payments enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_payments;
create policy tt_read_owner_v2 on public.tt_payments
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_payments to authenticated;
revoke insert, update, delete on public.tt_payments from anon, authenticated;

alter table public.tt_loyalty_ledger enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_loyalty_ledger;
create policy tt_read_owner_v2 on public.tt_loyalty_ledger
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_loyalty_ledger to authenticated;
revoke insert, update, delete on public.tt_loyalty_ledger from anon, authenticated;

alter table public.tt_inventory enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_inventory;
create policy tt_read_owner_v2 on public.tt_inventory
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_inventory to authenticated;
revoke insert, update, delete on public.tt_inventory from anon, authenticated;

alter table public.tt_cash_entries enable row level security;
drop policy if exists tt_read_owner_v2 on public.tt_cash_entries;
create policy tt_read_owner_v2 on public.tt_cash_entries
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.tt_cash_entries to authenticated;
revoke insert, update, delete on public.tt_cash_entries from anon, authenticated;

-- SECURITY DEFINER helper is private: callers cannot invoke this directly.
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
              then pg_catalog.floor(coalesce((x->>'paid')::numeric,0) / 10)::integer else 0 end,
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
  select p_user,x->>'id',x->>'customerId','earn',pg_catalog.floor(coalesce((x->>'paid')::numeric,0)/10)::integer
  from pg_catalog.jsonb_array_elements(coalesce(p->'orders','[]'::jsonb)) x
  where x->>'status'='Completed' and x->>'loyaltyEligible'='true' and nullif(x->>'customerId','') is not null
        and coalesce((x->>'paid')::numeric,0)>=10;
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
revoke all on function public.tt_project_business_state(uuid,jsonb) from public, anon, authenticated;

-- Sync projections even when an older deployed PWA calls the existing save_business_state RPC.
create or replace function public.tt_project_on_state_change()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
 perform public.tt_project_business_state(new.user_id,new.payload);
 return new;
end;
$fn$;
revoke all on function public.tt_project_on_state_change() from public, anon, authenticated;
drop trigger if exists tt_projection_sync_v2 on public.business_state;
create trigger tt_projection_sync_v2 after insert or update of payload on public.business_state
for each row execute function public.tt_project_on_state_change();

-- New safe versioned snapshot save; legacy save_business_state is not altered.
create or replace function public.tt_save_state_v2(expected_version bigint, next_payload jsonb)
returns bigint language plpgsql security definer set search_path = '' as $fn$
declare who uuid := (select auth.uid()); old_version bigint; new_version bigint;
begin
 if who is null then raise exception 'Please sign in' using errcode='28000'; end if;
 if pg_catalog.jsonb_typeof(next_payload) <> 'object' then raise exception 'Invalid business data'; end if;
 insert into public.business_state(user_id,payload,version)
 values(who,'{"products":[],"orders":[],"customers":[],"inventory":[],"cash":[],"staff":[]}'::jsonb,0)
 on conflict(user_id) do nothing;
 select version into old_version from public.business_state where user_id=who for update;
 if old_version is distinct from expected_version then
    raise exception 'STALE_VERSION: another device updated the data. Refresh and retry.' using errcode='40001';
 end if;
 update public.business_state set payload=next_payload,version=version+1 where user_id=who returning version into new_version;
 return new_version;
end;
$fn$;
revoke all on function public.tt_save_state_v2(bigint,jsonb) from public, anon;
grant execute on function public.tt_save_state_v2(bigint,jsonb) to authenticated;

-- Complete a POS sale atomically, with idempotent retries and authoritative stock/pricing.
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
   if redeem>points_balance then raise exception 'Insufficient customer loyalty points'; end if;
   if redeem::numeric/10>subtotal-discount then raise exception 'Points redemption exceeds payable amount'; end if;
 end if;
 total:=pg_catalog.round(subtotal-discount-redeem::numeric/10,2);
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
revoke all on function public.tt_checkout(bigint,jsonb) from public, anon;
grant execute on function public.tt_checkout(bigint,jsonb) to authenticated;

-- Void/refund a completed POS transaction atomically. No deletion of audit history.
create or replace function public.tt_void_sale(expected_version bigint, order_id text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
 who uuid:=(select auth.uid()); v bigint; st jsonb; os jsonb; prods jsonb; cas jsonb;
 ord jsonb; item jsonb; p jsonb; var jsonb; ix int; pi int; vi int; i int; j int;
 qty int; refund numeric; refund_id bigint; missing int:=0;
begin
 if who is null then raise exception 'Sign in required' using errcode='28000'; end if;
 select payload,version into st,v from public.business_state where user_id=who for update;
 if not found then raise exception 'Business data not found'; end if;
 os:=coalesce(st->'orders','[]'::jsonb);prods:=coalesce(st->'products','[]'::jsonb);
 cas:=coalesce(st->'cash','[]'::jsonb);
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
 update public.business_state set payload=st,version=version+1 where user_id=who returning version into v;
 return pg_catalog.jsonb_build_object('version',v,'order',ord,'missingStockItems',missing,'refundAmount',refund);
end;
$fn$;
revoke all on function public.tt_void_sale(bigint,text) from public, anon;
grant execute on function public.tt_void_sale(bigint,text) to authenticated;

-- Backfill the new relational tables without changing old payloads or versions.
do $backfill$
declare r record;
begin
  for r in select user_id,payload from public.business_state loop
    perform public.tt_project_business_state(r.user_id,r.payload);
  end loop;
end;
$backfill$;

commit;
