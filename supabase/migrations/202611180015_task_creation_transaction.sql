-- Atomic manager task creation and assignment.

create or replace function public.create_task_with_assignment(
  p_order_id uuid,
  p_department_id uuid,
  p_employee_id uuid,
  p_title text,
  p_description text,
  p_instructions text,
  p_priority public.task_priority,
  p_due_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_task_id uuid;
begin
  if auth.uid() is null or public.current_user_role() not in ('system_administrator', 'planning_manager', 'factory_manager', 'department_manager') then raise exception 'You are not authorized to create tasks'; end if;
  if p_title is null or length(trim(p_title)) = 0 then raise exception 'Task title is required'; end if;
  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then raise exception 'Order not found'; end if;
  if not exists (select 1 from public.departments d where d.id = p_department_id and d.factory_id = v_order.factory_id and d.is_active = true) then raise exception 'Department is not part of the order factory'; end if;
  if not exists (select 1 from public.profiles p join public.employee_factory_access efa on efa.employee_id = p.id and efa.factory_id = v_order.factory_id where p.id = p_employee_id and p.is_active = true) then raise exception 'Employee is not active or authorized for the order factory'; end if;

  insert into public.tasks (order_id, factory_id, department_id, title, description, instructions, priority, status, created_by, due_at)
  values (p_order_id, v_order.factory_id, p_department_id, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_instructions), ''), p_priority, 'assigned', auth.uid(), p_due_at)
  returning id into v_task_id;
  insert into public.task_assignments (task_id, employee_id) values (v_task_id, p_employee_id);
  insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id) values (p_employee_id, 'task_assignment', 'New task assignment', trim(p_title), p_order_id, v_task_id);
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'create_task', 'task', v_task_id, jsonb_build_object('order_id', p_order_id, 'employee_id', p_employee_id));
  return v_task_id;
end;
$$;

revoke execute on function public.create_task_with_assignment(uuid, uuid, uuid, text, text, text, public.task_priority, timestamptz) from public;
grant execute on function public.create_task_with_assignment(uuid, uuid, uuid, text, text, text, public.task_priority, timestamptz) to authenticated;
