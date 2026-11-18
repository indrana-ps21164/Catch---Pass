-- Atomic task acceptance/rejection response.

create or replace function public.respond_to_task(
  p_assignment_id uuid,
  p_response text,
  p_reason text
)
returns public.task_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.task_assignments%rowtype;
  v_task public.tasks%rowtype;
  v_new_status public.task_status;
begin
  if auth.uid() is null or p_response not in ('accepted', 'rejected', 'clarification_requested') then raise exception 'Invalid task response'; end if;
  if p_response in ('rejected', 'clarification_requested') and (p_reason is null or length(trim(p_reason)) = 0) then raise exception 'A reason is required'; end if;
  select * into v_assignment from public.task_assignments where id = p_assignment_id and employee_id = auth.uid() for update;
  if v_assignment.id is null then raise exception 'Assignment not found or not assigned to you'; end if;
  select * into v_task from public.tasks where id = v_assignment.task_id for update;
  if v_task.id is null or v_task.status in ('cancelled', 'approved', 'submitted') then raise exception 'Task cannot accept a response in its current status'; end if;

  v_new_status := case when p_response = 'accepted' then 'accepted'::public.task_status when p_response = 'rejected' then 'rejected'::public.task_status else 'ready'::public.task_status end;
  update public.task_assignments set acceptance_status = p_response, accepted_at = case when p_response = 'accepted' then now() else accepted_at end, rejected_at = case when p_response = 'rejected' then now() else rejected_at end, rejection_reason = case when p_response <> 'accepted' then trim(p_reason) else null end where id = p_assignment_id;
  update public.tasks set status = v_new_status, updated_at = now() where id = v_task.id;
  insert into public.task_history (task_id, actor_id, previous_status, new_status, remarks) values (v_task.id, auth.uid(), v_task.status, v_new_status, nullif(trim(p_reason), ''));
  if v_task.created_by is not null and v_task.created_by <> auth.uid() then insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id) values (v_task.created_by, 'task_response', 'Task response received', coalesce(p_reason, p_response), v_task.order_id, v_task.id); end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'respond_to_task', 'task_assignment', p_assignment_id, jsonb_build_object('response', p_response));
  return v_new_status;
end;
$$;

revoke execute on function public.respond_to_task(uuid, text, text) from public;
grant execute on function public.respond_to_task(uuid, text, text) to authenticated;
