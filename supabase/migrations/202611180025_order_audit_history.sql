-- Preserve order creation and status/field changes in the existing audit log.

create or replace function public.audit_order_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
    values (coalesce(auth.uid(), new.created_by), 'create_order', 'order', new.id, jsonb_build_object('status', new.status, 'order_number', new.order_number));
  elsif tg_op = 'UPDATE' then
    if old.status is distinct from new.status or old.customer_name is distinct from new.customer_name or old.required_delivery_date is distinct from new.required_delivery_date or old.priority is distinct from new.priority or old.cancellation_reason is distinct from new.cancellation_reason then
      insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
      values (auth.uid(), 'update_order', 'order', new.id, jsonb_build_object('previous_status', old.status, 'status', new.status, 'order_number', new.order_number));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_audit_change on public.orders;
create trigger orders_audit_change
  after insert or update on public.orders
  for each row execute function public.audit_order_change();

revoke execute on function public.audit_order_change() from public;
