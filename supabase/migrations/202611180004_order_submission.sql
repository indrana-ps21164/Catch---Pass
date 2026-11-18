-- Phase 2: validated order submission.

create or replace function public.submit_order(p_order_id uuid)
returns public.order_status
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status public.order_status;
  v_created_by uuid;
begin
  select status, created_by into v_status, v_created_by
  from public.orders where id = p_order_id for update;

  if v_status is null then raise exception 'Order not found'; end if;
  if v_status <> 'draft' then raise exception 'Only draft orders can be submitted'; end if;
  if v_created_by <> auth.uid() and public.current_user_role() not in ('system_administrator', 'planning_manager', 'factory_manager') then
    raise exception 'You are not authorized to submit this order';
  end if;
  if not exists (select 1 from public.order_items where order_id = p_order_id) then
    raise exception 'Add at least one product line before submitting';
  end if;

  update public.orders set status = 'submitted', updated_at = now() where id = p_order_id;
  return 'submitted';
end;
$$;

revoke execute on function public.submit_order(uuid) from public;
grant execute on function public.submit_order(uuid) to authenticated;
