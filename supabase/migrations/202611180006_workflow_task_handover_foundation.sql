-- Phase 3/4/5 foundation: workflow, tasks, manual handovers, notifications and audit history.

create type public.task_status as enum ('not_started', 'ready', 'assigned', 'accepted', 'in_progress', 'submitted', 'approved', 'rejected', 'blocked', 'cancelled');
create type public.task_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.assignment_mode as enum ('individual', 'collaborative');
create type public.handover_status as enum ('pending', 'accepted', 'partially_accepted', 'rejected', 'completed', 'cancelled');

create table public.workflow_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  factory_id uuid references public.factories(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workflow_steps (
  id uuid primary key default gen_random_uuid(),
  workflow_template_id uuid not null references public.workflow_templates(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete restrict,
  title text not null,
  description text,
  sequence_number integer not null check (sequence_number > 0),
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  unique(workflow_template_id, sequence_number)
);

create table public.order_workflows (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  workflow_template_id uuid not null references public.workflow_templates(id) on delete restrict,
  current_step_id uuid references public.workflow_steps(id) on delete set null,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  workflow_step_id uuid references public.workflow_steps(id) on delete set null,
  factory_id uuid not null references public.factories(id) on delete restrict,
  department_id uuid not null references public.departments(id) on delete restrict,
  title text not null,
  description text,
  instructions text,
  priority public.task_priority not null default 'normal',
  status public.task_status not null default 'not_started',
  task_lead_id uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  started_at timestamptz,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.task_dependencies (
  task_id uuid not null references public.tasks(id) on delete cascade,
  depends_on_task_id uuid not null references public.tasks(id) on delete cascade,
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(task_id, depends_on_task_id),
  constraint task_cannot_depend_on_itself check (task_id <> depends_on_task_id)
);

create table public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete restrict,
  is_lead boolean not null default false,
  acceptance_status text not null default 'pending' check (acceptance_status in ('pending', 'accepted', 'rejected', 'clarification_requested')),
  accepted_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  unique(task_id, employee_id)
);

create table public.handovers (
  id uuid primary key default gen_random_uuid(),
  source_task_id uuid not null references public.tasks(id) on delete restrict,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  assignment_mode public.assignment_mode not null,
  instructions text not null,
  expected_outcome text,
  priority public.task_priority not null default 'normal',
  due_at timestamptz,
  status public.handover_status not null default 'pending',
  completion_remarks text,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(source_task_id, confirmed_at)
);

create table public.handover_recipients (
  id uuid primary key default gen_random_uuid(),
  handover_id uuid not null references public.handovers(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  task_id uuid references public.tasks(id) on delete set null,
  is_lead boolean not null default false,
  individual_description text,
  response_status text not null default 'pending' check (response_status in ('pending', 'accepted', 'rejected', 'clarification_requested')),
  response_reason text,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  unique(handover_id, recipient_id)
);

create table public.task_history (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  previous_status public.task_status,
  new_status public.task_status,
  remarks text,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  body text not null,
  order_id uuid references public.orders(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete cascade,
  handover_id uuid references public.handovers(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index tasks_order_id_idx on public.tasks(order_id);
create index tasks_department_status_idx on public.tasks(department_id, status);
create index tasks_due_at_idx on public.tasks(due_at);
create index task_assignments_employee_idx on public.task_assignments(employee_id, acceptance_status);
create index handovers_source_task_idx on public.handovers(source_task_id);
create index handover_recipients_recipient_idx on public.handover_recipients(recipient_id, response_status);
create index notifications_recipient_unread_idx on public.notifications(recipient_id, is_read, created_at desc);
create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, created_at desc);

alter table public.workflow_templates enable row level security;
alter table public.workflow_steps enable row level security;
alter table public.order_workflows enable row level security;
alter table public.tasks enable row level security;
alter table public.task_dependencies enable row level security;
alter table public.task_assignments enable row level security;
alter table public.handovers enable row level security;
alter table public.handover_recipients enable row level security;
alter table public.task_history enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

create policy "Authorized users view workflow templates" on public.workflow_templates for select to authenticated using (public.current_user_role() is not null);
create policy "Managers manage workflow templates" on public.workflow_templates for all to authenticated using (public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager')) with check (public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager'));
create policy "Authorized users view workflow steps" on public.workflow_steps for select to authenticated using (exists (select 1 from public.workflow_templates wt where wt.id = workflow_steps.workflow_template_id));
create policy "Managers manage workflow steps" on public.workflow_steps for all to authenticated using (public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager')) with check (public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager'));

create policy "Authorized users view tasks" on public.tasks for select to authenticated using (
  created_by = auth.uid() or task_lead_id = auth.uid() or exists (select 1 from public.task_assignments ta where ta.task_id = tasks.id and ta.employee_id = auth.uid()) or public.current_user_role() in ('system_administrator', 'management_viewer', 'factory_manager', 'department_manager', 'planning_manager')
);
create policy "Authorized users create tasks" on public.tasks for insert to authenticated with check (created_by = auth.uid() and public.current_user_role() in ('system_administrator', 'planning_manager', 'factory_manager', 'department_manager'));
create policy "Task owners update tasks" on public.tasks for update to authenticated using (created_by = auth.uid() or task_lead_id = auth.uid() or exists (select 1 from public.task_assignments ta where ta.task_id = tasks.id and ta.employee_id = auth.uid()) or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager')) with check (created_by = auth.uid() or task_lead_id = auth.uid() or exists (select 1 from public.task_assignments ta where ta.task_id = tasks.id and ta.employee_id = auth.uid()) or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager'));
create policy "Task participants view assignments" on public.task_assignments for select to authenticated using (employee_id = auth.uid() or exists (select 1 from public.tasks t where t.id = task_assignments.task_id and (t.created_by = auth.uid() or t.task_lead_id = auth.uid())) or public.current_user_role() in ('system_administrator', 'management_viewer', 'department_manager'));
create policy "Authorized users create assignments" on public.task_assignments for insert to authenticated with check (exists (select 1 from public.tasks t where t.id = task_assignments.task_id and (t.created_by = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager'))));
create policy "Participants update assignments" on public.task_assignments for update to authenticated using (employee_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager')) with check (employee_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager'));

create policy "Handover participants view handovers" on public.handovers for select to authenticated using (sender_id = auth.uid() or exists (select 1 from public.handover_recipients hr where hr.handover_id = handovers.id and hr.recipient_id = auth.uid()) or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager', 'management_viewer'));
create policy "Authorized users create handovers" on public.handovers for insert to authenticated with check (sender_id = auth.uid() and public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager', 'planning_manager'));
create policy "Handover participants update handovers" on public.handovers for update to authenticated using (sender_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager')) with check (sender_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager'));
create policy "Handover participants view recipients" on public.handover_recipients for select to authenticated using (recipient_id = auth.uid() or exists (select 1 from public.handovers h where h.id = handover_recipients.handover_id and h.sender_id = auth.uid()) or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager', 'management_viewer'));
create policy "Authorized users create recipients" on public.handover_recipients for insert to authenticated with check (exists (select 1 from public.handovers h where h.id = handover_recipients.handover_id and h.sender_id = auth.uid()));
create policy "Recipients update their response" on public.handover_recipients for update to authenticated using (recipient_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager')) with check (recipient_id = auth.uid() or public.current_user_role() in ('system_administrator', 'factory_manager', 'department_manager'));

create policy "Task participants view history" on public.task_history for select to authenticated using (actor_id = auth.uid() or exists (select 1 from public.tasks t where t.id = task_history.task_id and (t.created_by = auth.uid() or t.task_lead_id = auth.uid())) or public.current_user_role() in ('system_administrator', 'management_viewer', 'department_manager'));
create policy "Authenticated users create history" on public.task_history for insert to authenticated with check (actor_id = auth.uid());
create policy "Users view own notifications" on public.notifications for select to authenticated using (recipient_id = auth.uid());
create policy "Users update own notifications" on public.notifications for update to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
create policy "Users view relevant audit logs" on public.audit_logs for select to authenticated using (actor_id = auth.uid() or public.current_user_role() in ('system_administrator', 'management_viewer'));

grant select, insert, update on public.workflow_templates, public.workflow_steps, public.order_workflows, public.tasks, public.task_dependencies, public.task_assignments, public.handovers, public.handover_recipients, public.task_history, public.notifications, public.audit_logs to authenticated;
