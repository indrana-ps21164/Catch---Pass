-- Critical business transaction: Complete & Pass.

alter table public.handovers add column if not exists idempotency_key uuid;
create unique index if not exists handovers_idempotency_key_idx on public.handovers(idempotency_key) where idempotency_key is not null;

drop policy if exists "Employees view their own profile" on public.profiles;
create policy "Employees view authorized colleagues" on public.profiles for select to authenticated using (
  id = auth.uid()
  or public.current_user_role() = 'system_administrator'
  or exists (
    select 1 from public.employee_factory_access mine
    join public.employee_factory_access colleague on colleague.factory_id = mine.factory_id
    where mine.employee_id = auth.uid() and colleague.employee_id = profiles.id and profiles.is_active = true
  )
);

drop policy if exists "Authorized users create tasks" on public.tasks;
create policy "Authorized users create tasks" on public.tasks for insert to authenticated with check (
  created_by = auth.uid() and public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager', 'department_manager', 'department_employee')
);

drop policy if exists "Authorized users create handovers" on public.handovers;
create policy "Authorized users create handovers" on public.handovers for insert to authenticated with check (
  sender_id = auth.uid() and exists (select 1 from public.tasks t where t.id = handovers.source_task_id and (t.created_by = auth.uid() or t.task_lead_id = auth.uid() or exists (select 1 from public.task_assignments ta where ta.task_id = t.id and ta.employee_id = auth.uid())))
);

create policy "Authenticated users create notifications" on public.notifications for insert to authenticated with check (recipient_id is not null);

create or replace function public.complete_and_pass(
  p_source_task_id uuid,
  p_completion_remarks text,
  p_assignment_mode public.assignment_mode,
  p_instructions text,
  p_expected_outcome text,
  p_priority public.task_priority,
  p_due_at timestamptz,
  p_recipients jsonb,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.tasks%rowtype;
  v_handover_id uuid;
  v_new_task_id uuid;
  v_recipient jsonb;
  v_count integer;
  v_lead_count integer;
  v_recipient_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if p_instructions is null or length(trim(p_instructions)) = 0 then raise exception 'Handover instructions are required'; end if;
  if jsonb_typeof(p_recipients) <> 'array' or jsonb_array_length(p_recipients) = 0 then raise exception 'Select at least one recipient'; end if;
  if p_assignment_mode = 'collaborative' and (select count(*) from jsonb_array_elements(p_recipients) r where coalesce((r->>'is_lead')::boolean, false)) <> 1 then raise exception 'A collaborative handover requires exactly one lead'; end if;

  select t.* into v_source from public.tasks t where t.id = p_source_task_id for update;
  if v_source.id is null then raise exception 'Source task not found'; end if;
  if not (v_source.created_by = auth.uid() or v_source.task_lead_id = auth.uid() or exists (select 1 from public.task_assignments ta where ta.task_id = v_source.id and ta.employee_id = auth.uid())) then raise exception 'You are not responsible for this task'; end if;
  if v_source.status in ('submitted', 'approved', 'cancelled') then raise exception 'This task cannot be handed over from its current status'; end if;

  if p_idempotency_key is not null then
    select id into v_handover_id from public.handovers where idempotency_key = p_idempotency_key;
    if v_handover_id is not null then return v_handover_id; end if;
  end if;

  select count(*) into v_count from jsonb_array_elements(p_recipients) r;
  if exists (select 1 from jsonb_array_elements(p_recipients) r where not exists (select 1 from public.profiles p join public.employee_factory_access efa on efa.employee_id = p.id and efa.factory_id = v_source.factory_id where p.id = (r->>'employee_id')::uuid and p.is_active = true)) then raise exception 'Every recipient must be active and authorized for the source factory'; end if;

  insert into public.handovers (source_task_id, sender_id, assignment_mode, instructions, expected_outcome, priority, due_at, completion_remarks, idempotency_key)
  values (v_source.id, auth.uid(), p_assignment_mode, trim(p_instructions), nullif(trim(p_expected_outcome), ''), p_priority, p_due_at, p_completion_remarks, p_idempotency_key)
  returning id into v_handover_id;

  update public.tasks set status = 'submitted', completed_at = now(), updated_at = now() where id = v_source.id;
  insert into public.task_history (task_id, actor_id, previous_status, new_status, remarks) values (v_source.id, auth.uid(), v_source.status, 'submitted', p_completion_remarks);

  if p_assignment_mode = 'collaborative' then
    select (r->>'employee_id')::uuid into v_recipient_id from jsonb_array_elements(p_recipients) r where coalesce((r->>'is_lead')::boolean, false) limit 1;
    insert into public.tasks (order_id, workflow_step_id, factory_id, department_id, title, description, instructions, priority, status, task_lead_id, created_by, due_at)
    values (v_source.order_id, v_source.workflow_step_id, v_source.factory_id, v_source.department_id, v_source.title, v_source.description, p_instructions, p_priority, 'assigned', v_recipient_id, auth.uid(), p_due_at)
    returning id into v_new_task_id;
    for v_recipient in select value from jsonb_array_elements(p_recipients) loop
      insert into public.task_assignments (task_id, employee_id, is_lead) values (v_new_task_id, (v_recipient->>'employee_id')::uuid, coalesce((v_recipient->>'is_lead')::boolean, false));
      insert into public.handover_recipients (handover_id, recipient_id, task_id, is_lead, individual_description) values (v_handover_id, (v_recipient->>'employee_id')::uuid, v_new_task_id, coalesce((v_recipient->>'is_lead')::boolean, false), nullif(trim(v_recipient->>'description'), ''));
      insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id, handover_id) values ((v_recipient->>'employee_id')::uuid, 'handover_received', 'New collaborative handover', trim(p_instructions), v_source.order_id, v_new_task_id, v_handover_id);
    end loop;
  else
    for v_recipient in select value from jsonb_array_elements(p_recipients) loop
      insert into public.tasks (order_id, workflow_step_id, factory_id, department_id, title, description, instructions, priority, status, created_by, due_at)
      values (v_source.order_id, v_source.workflow_step_id, v_source.factory_id, v_source.department_id, v_source.title, nullif(trim(v_recipient->>'description'), ''), p_instructions, p_priority, 'assigned', auth.uid(), p_due_at)
      returning id into v_new_task_id;
      insert into public.task_assignments (task_id, employee_id) values (v_new_task_id, (v_recipient->>'employee_id')::uuid);
      insert into public.handover_recipients (handover_id, recipient_id, task_id, individual_description) values (v_handover_id, (v_recipient->>'employee_id')::uuid, v_new_task_id, nullif(trim(v_recipient->>'description'), ''));
      insert into public.notifications (recipient_id, notification_type, title, body, order_id, task_id, handover_id) values ((v_recipient->>'employee_id')::uuid, 'handover_received', 'New task handover', trim(p_instructions), v_source.order_id, v_new_task_id, v_handover_id);
    end loop;
  end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), 'complete_and_pass', 'handover', v_handover_id, jsonb_build_object('source_task_id', v_source.id, 'assignment_mode', p_assignment_mode, 'recipient_count', v_count));
  return v_handover_id;
end;
$$;

revoke execute on function public.complete_and_pass(uuid, text, public.assignment_mode, text, text, public.task_priority, timestamptz, jsonb, uuid) from public;
grant execute on function public.complete_and_pass(uuid, text, public.assignment_mode, text, text, public.task_priority, timestamptz, jsonb, uuid) to authenticated;
