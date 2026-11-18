-- Atomic task work updates and manager approval.

alter table public.tasks add column if not exists progress_percent integer not null default 0 check (progress_percent between 0 and 100);
alter table public.tasks add column if not exists completion_remarks text;

create or replace function public.update_task_work(
  p_task_id uuid,
  p_status text,
  p_progress_percent integer,
  p_remarks text
)
returns public.task_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks%rowtype;
  v_assignment public.task_assignments%rowtype;
  v_new_status public.task_status;
begin
  if auth.uid() is null or p_status not in ('in_progress', 'submitted', 'blocked') then raise exception 'Invalid task work status'; end if;
  if p_progress_percent is null or p_progress_percent < 0 or p_progress_percent > 100 then raise exception 'Progress must be between 0 and 100'; end if;
  if p_status = 'submitted' and (p_remarks is null or length(trim(p_remarks)) = 0) then raise exception 'Completion remarks are required before submitting'; end if;
  select * into v_task from public.tasks where id = p_task_id for update;
  if v_task.id is null or v_task.status in ('cancelled', 'approved', 'submitted') then raise exception 'Task cannot be updated in its current status'; end if;
  select * into v_assignment from public.task_assignments where task_id = p_task_id and employee_id = auth.uid() for update;
  if v_assignment.id is null or v_assignment.acceptance_status <> 'accepted' then raise exception 'Accept the task before updating work'; end if;
  v_new_status := p_status::public.task_status;
  update public.tasks
    set status = v_new_status,
        progress_percent = case when p_status = 'submitted' then 100 else p_progress_percent end,
        started_at = case when p_status = 'in_progress' and started_at is null then now() else started_at end,
        completed_at = case when p_status = 'submitted' then now() else completed_at end,
        completion_remarks = case when p_status = 'submitted' then nullif(trim(p_remarks), '') else completion_remarks end,
        updated_at = now()
    where id = p_task_id;
  insert into public.task_history (task_id, actor_id, previous_status, new_status, remarks) values (p_task_id, auth.uid(), v_task.status, v_new_status, nullif(trim(p_remarks), ''));
  if v_task.created_by is not null and v_task.created_by <> auth.uid() then
    insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id) values (v_task.created_by, 'task_progress', 'Task status updated', coalesce(nullif(trim(p_remarks), ''), replace(p_status, '_', ' ')), v_task.order_id, p_task_id);
  end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'update_task_work', 'task', p_task_id, jsonb_build_object('status', p_status, 'progress_percent', p_progress_percent));
  return v_new_status;
end;
$$;

create or replace function public.approve_task(p_task_id uuid, p_remarks text)
returns public.task_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks%rowtype;
  v_role public.app_role;
  v_new_status public.task_status := 'approved';
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_role := public.current_user_role();
  if v_role not in ('system_administrator', 'factory_manager', 'department_manager', 'planning_manager', 'qa_approver') then raise exception 'You are not authorized to approve tasks'; end if;
  select * into v_task from public.tasks where id = p_task_id for update;
  if v_task.id is null or v_task.status <> 'submitted' then raise exception 'Only submitted tasks can be approved'; end if;
  if not exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = v_task.factory_id) then raise exception 'You are not authorized for this factory'; end if;
  update public.tasks set status = v_new_status, updated_at = now() where id = p_task_id;
  insert into public.task_history (task_id, actor_id, previous_status, new_status, remarks) values (p_task_id, auth.uid(), v_task.status, v_new_status, nullif(trim(p_remarks), ''));
  if v_task.created_by is not null and v_task.created_by <> auth.uid() then
    insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id) values (v_task.created_by, 'task_approval', 'Task approved', coalesce(nullif(trim(p_remarks), ''), 'The submitted task was approved.'), v_task.order_id, p_task_id);
  end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'approve_task', 'task', p_task_id, jsonb_build_object('remarks', p_remarks));
  return v_new_status;
end;
$$;

revoke execute on function public.update_task_work(uuid, text, integer, text) from public;
revoke execute on function public.approve_task(uuid, text) from public;
grant execute on function public.update_task_work(uuid, text, integer, text) to authenticated;
grant execute on function public.approve_task(uuid, text) to authenticated;
