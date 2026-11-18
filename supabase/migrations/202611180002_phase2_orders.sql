-- Phase 2: factories, departments, and real order registration.

create type public.order_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.order_status as enum ('draft', 'submitted', 'in_progress', 'on_hold', 'delayed', 'ready_for_dispatch', 'partially_shipped', 'completed', 'cancelled');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  customer_name text not null check (length(trim(customer_name)) > 0),
  customer_reference text,
  factory_id uuid not null references public.factories(id) on delete restrict,
  order_date date not null default current_date,
  required_delivery_date date not null,
  priority public.order_priority not null default 'normal',
  customer_remarks text,
  internal_remarks text,
  status public.order_status not null default 'draft',
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_delivery_date check (required_delivery_date >= order_date)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_code text not null check (length(trim(product_code)) > 0),
  product_description text not null check (length(trim(product_description)) > 0),
  quantity numeric(14,3) not null check (quantity > 0),
  unit_of_measurement text not null check (length(trim(unit_of_measurement)) > 0),
  remarks text,
  created_at timestamptz not null default now()
);

create index orders_factory_id_idx on public.orders(factory_id);
create index orders_status_idx on public.orders(status);
create index orders_delivery_date_idx on public.orders(required_delivery_date);
create index orders_customer_name_idx on public.orders using gin (to_tsvector('simple', customer_name));
create index order_items_order_id_idx on public.order_items(order_id);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

revoke execute on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;

create policy "Authorized users view orders"
  on public.orders for select to authenticated using (
    public.current_user_role() in ('system_administrator', 'management_viewer', 'planning_manager', 'factory_manager', 'department_manager', 'qa_approver', 'dispatch_officer')
    and exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id)
  );
create policy "Authorized users create orders"
  on public.orders for insert to authenticated with check (
    public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager')
    and created_by = auth.uid()
    and exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id)
  );
create policy "Authorized users update draft orders"
  on public.orders for update to authenticated using (
    (created_by = auth.uid() or public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager'))
    and exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id)
  ) with check (exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id));

create policy "Authorized users view order items"
  on public.order_items for select to authenticated using (exists (select 1 from public.orders o where o.id = order_items.order_id));
create policy "Authorized users create order items"
  on public.order_items for insert to authenticated with check (exists (select 1 from public.orders o where o.id = order_items.order_id and o.created_by = auth.uid()));
create policy "Authorized users update order items"
  on public.order_items for update to authenticated using (exists (select 1 from public.orders o where o.id = order_items.order_id and o.created_by = auth.uid())) with check (exists (select 1 from public.orders o where o.id = order_items.order_id and o.created_by = auth.uid()));

grant select, insert, update on public.orders to authenticated;
grant select, insert, update on public.order_items to authenticated;
