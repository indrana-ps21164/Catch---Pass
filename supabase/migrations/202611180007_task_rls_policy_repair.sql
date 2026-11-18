-- Repair: avoid recursive RLS evaluation between tasks and task assignments.

drop policy if exists "Authorized users view tasks" on public.tasks;
drop policy if exists "Task participants view assignments" on public.task_assignments;
drop policy if exists "Handover participants view handovers" on public.handovers;
drop policy if exists "Handover participants view recipients" on public.handover_recipients;

create policy "Authorized users view tasks" on public.tasks for select to authenticated using (
  created_by = auth.uid() or task_lead_id = auth.uid() or public.current_user_role() in ('system_administrator', 'management_viewer', 'factory_manager', 'department_manager', 'planning_manager') or exists (select 1 from public.task_assignments ta where ta.task_id = tasks.id and ta.employee_id = auth.uid())
);

create policy "Task participants view assignments" on public.task_assignments for select to authenticated using (
  employee_id = auth.uid() or public.current_user_role() in ('system_administrator', 'management_viewer', 'department_manager', 'factory_manager')
);

create policy "Handover participants view handovers" on public.handovers for select to authenticated using (
  sender_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager', 'management_viewer') or exists (select 1 from public.handover_recipients hr where hr.handover_id = handovers.id and hr.recipient_id = auth.uid())
);

create policy "Handover participants view recipients" on public.handover_recipients for select to authenticated using (
  recipient_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager', 'management_viewer')
);
