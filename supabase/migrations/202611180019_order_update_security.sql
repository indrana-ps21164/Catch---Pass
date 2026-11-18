-- Restrict ordinary creators to draft edits; use a validated function for cancellation.

drop policy if exists "Authorized users update draft orders" on public.orders;
create policy "Authorized users update draft orders" on public.orders for update to authenticated using (
  exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id)
  and ((created_by = auth.uid() and status = 'draft') or public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager'))
) with check (
  exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = orders.factory_id)
  and ((created_by = auth.uid() and status = 'draft') or public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager'))
);

create or replace function public.cancel_order(p_order_id uuid, p_reason text)
returns public.order_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null or p_reason is null or length(trim(p_reason)) = 0 then raise exception 'Authentication and a cancellation reason are required'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Order not found'; end if;
  if v_order.created_by <> auth.uid() and public.current_user_role() not in ('system_administrator', 'planning_manager', 'factory_manager') then raise exception 'You are not authorized to cancel this order'; end if;
  if v_order.status in ('completed', 'cancelled') then raise exception 'This order cannot be cancelled'; end if;
  update public.orders set status = 'cancelled', cancellation_reason = trim(p_reason), updated_at = now() where id = p_order_id;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'cancel_order', 'order', p_order_id, jsonb_build_object('reason', trim(p_reason)));
  return 'cancelled';
end;
$$;

revoke execute on function public.cancel_order(uuid, text) from public;
grant execute on function public.cancel_order(uuid, text) to authenticated;
