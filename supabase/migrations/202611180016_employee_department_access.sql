-- Employee-to-department authorization.

create table public.employee_department_access (
  employee_id uuid not null references public.profiles(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(employee_id, department_id)
);

create index employee_department_access_department_idx on public.employee_department_access(department_id);
alter table public.employee_department_access enable row level security;

create policy "Employees view their department access" on public.employee_department_access for select to authenticated using (employee_id = auth.uid() or public.current_user_role() = 'system_administrator' or public.current_user_role() in ('factory_manager', 'department_manager'));
create policy "Administrators manage department access" on public.employee_department_access for all to authenticated using (public.current_user_role() = 'system_administrator') with check (public.current_user_role() = 'system_administrator');
grant select on public.employee_department_access to authenticated;
