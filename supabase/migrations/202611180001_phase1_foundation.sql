-- Catch & Pass Phase 1 foundation
-- Run this migration in Supabase SQL Editor or with Supabase CLI.

create extension if not exists "pgcrypto";

create type public.app_role as enum (
  'system_administrator', 'factory_manager', 'planning_manager',
  'department_manager', 'department_employee', 'qa_approver',
  'dispatch_officer', 'management_viewer'
);

create table public.factories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id) on delete restrict,
  name text not null,
  description text,
  manager_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(factory_id, name)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  role public.app_role not null default 'department_employee',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.departments add constraint departments_manager_id_fkey foreign key (manager_id) references public.profiles(id) on delete set null;

create table public.employee_factory_access (
  employee_id uuid not null references public.profiles(id) on delete cascade,
  factory_id uuid not null references public.factories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(employee_id, factory_id)
);

create index departments_factory_id_idx on public.departments(factory_id);
create index profiles_role_idx on public.profiles(role);
create index employee_factory_access_factory_id_idx on public.employee_factory_access(factory_id);

alter table public.factories enable row level security;
alter table public.departments enable row level security;
alter table public.profiles enable row level security;
alter table public.employee_factory_access enable row level security;

create or replace function public.current_user_role()
returns public.app_role language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and is_active = true $$;

create policy "Authenticated users can view active factories"
  on public.factories for select to authenticated using (is_active = true or public.current_user_role() = 'system_administrator');
create policy "Administrators manage factories"
  on public.factories for all to authenticated using (public.current_user_role() = 'system_administrator') with check (public.current_user_role() = 'system_administrator');

create policy "Authorized users can view departments"
  on public.departments for select to authenticated using (
    public.current_user_role() in ('system_administrator', 'management_viewer')
    or exists (select 1 from public.employee_factory_access efa where efa.employee_id = auth.uid() and efa.factory_id = departments.factory_id)
  );
create policy "Administrators manage departments"
  on public.departments for all to authenticated using (public.current_user_role() = 'system_administrator') with check (public.current_user_role() = 'system_administrator');

create policy "Employees view their own profile"
  on public.profiles for select to authenticated using (id = auth.uid() or public.current_user_role() = 'system_administrator');
create policy "Administrators manage profiles"
  on public.profiles for all to authenticated using (public.current_user_role() = 'system_administrator') with check (public.current_user_role() = 'system_administrator');
create policy "Employees view their factory access"
  on public.employee_factory_access for select to authenticated using (employee_id = auth.uid() or public.current_user_role() = 'system_administrator');
create policy "Administrators manage factory access"
  on public.employee_factory_access for all to authenticated using (public.current_user_role() = 'system_administrator') with check (public.current_user_role() = 'system_administrator');

-- New auth users receive a profile only after an administrator completes the employee record.
