-- Shipment management and validated partial-shipment transaction.

create table public.shipments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  shipment_reference text not null,
  shipment_date date not null default current_date,
  delivery_reference text,
  remarks text,
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(order_id, shipment_reference)
);

create table public.shipment_items (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete restrict,
  quantity_shipped numeric(14,3) not null check (quantity_shipped > 0),
  created_at timestamptz not null default now()
);

create index shipments_order_id_idx on public.shipments(order_id, shipment_date desc);
create index shipment_items_order_item_id_idx on public.shipment_items(order_item_id);
alter table public.shipments enable row level security;
alter table public.shipment_items enable row level security;

create policy "Authorized users view shipments" on public.shipments for select to authenticated using (
  recorded_by = auth.uid() or public.current_user_role() in ('system_administrator', 'management_viewer', 'dispatch_officer', 'factory_manager', 'planning_manager') or exists (select 1 from public.orders o where o.id = shipments.order_id)
);
create policy "Dispatch users create shipments" on public.shipments for insert to authenticated with check (recorded_by = auth.uid() and public.current_user_role() in ('system_administrator', 'dispatch_officer', 'factory_manager'));
create policy "Authorized users view shipment items" on public.shipment_items for select to authenticated using (exists (select 1 from public.shipments s where s.id = shipment_items.shipment_id));
create policy "Dispatch users create shipment items" on public.shipment_items for insert to authenticated with check (exists (select 1 from public.shipments s where s.id = shipment_items.shipment_id and s.recorded_by = auth.uid()));

create or replace function public.record_shipment(
  p_order_id uuid,
  p_shipment_reference text,
  p_shipment_date date,
  p_delivery_reference text,
  p_remarks text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shipment_id uuid;
  v_item jsonb;
  v_order_item public.order_items%rowtype;
  v_already_shipped numeric;
  v_requested numeric;
  v_total_remaining numeric;
  v_total_ordered numeric;
  v_total_shipped numeric;
begin
  if auth.uid() is null or public.current_user_role() not in ('system_administrator', 'dispatch_officer', 'factory_manager') then raise exception 'You are not authorized to record shipments'; end if;
  if p_shipment_reference is null or length(trim(p_shipment_reference)) = 0 then raise exception 'Shipment reference is required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'At least one shipment line is required'; end if;

  if not exists (select 1 from public.orders where id = p_order_id) then raise exception 'Order not found'; end if;
  insert into public.shipments (order_id, shipment_reference, shipment_date, delivery_reference, remarks, recorded_by)
  values (p_order_id, trim(p_shipment_reference), p_shipment_date, nullif(trim(p_delivery_reference), ''), nullif(trim(p_remarks), ''), auth.uid())
  returning id into v_shipment_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_order_item from public.order_items where id = (v_item->>'order_item_id')::uuid and order_id = p_order_id for update;
    if v_order_item.id is null then raise exception 'Shipment line references an invalid order item'; end if;
    v_requested := (v_item->>'quantity')::numeric;
    select coalesce(sum(quantity_shipped), 0) into v_already_shipped from public.shipment_items where order_item_id = v_order_item.id;
    if v_requested <= 0 or v_already_shipped + v_requested > v_order_item.quantity then raise exception 'Shipment quantity exceeds the remaining quantity for %', v_order_item.product_code; end if;
    insert into public.shipment_items (shipment_id, order_item_id, quantity_shipped) values (v_shipment_id, v_order_item.id, v_requested);
  end loop;

  select coalesce(sum(oi.quantity), 0), coalesce(sum(si.quantity_shipped), 0) into v_total_ordered, v_total_shipped
  from public.order_items oi left join public.shipment_items si on si.order_item_id = oi.id where oi.order_id = p_order_id;
  if v_total_ordered > 0 and v_total_shipped >= v_total_ordered then update public.orders set status = 'completed', updated_at = now() where id = p_order_id;
  else update public.orders set status = 'partially_shipped', updated_at = now() where id = p_order_id and status not in ('cancelled', 'completed'); end if;
  return v_shipment_id;
end;
$$;

revoke execute on function public.record_shipment(uuid, text, date, text, text, jsonb) from public;
grant execute on function public.record_shipment(uuid, text, date, text, text, jsonb) to authenticated;
grant select, insert on public.shipments, public.shipment_items to authenticated;
