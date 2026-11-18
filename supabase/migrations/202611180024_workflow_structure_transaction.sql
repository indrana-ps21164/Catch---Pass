-- Store workflow structure metadata without automatically assigning any employee.

alter table public.workflow_templates
  add column if not exists workflow_structure text not null default 'sequential'
    check (workflow_structure in ('sequential', 'parallel', 'conditional'));
alter table public.workflow_templates add column if not exists condition_definition text;

create or replace function public.create_workflow_template_v2(
  p_name text,
  p_description text,
  p_factory_id uuid,
  p_workflow_structure text,
  p_condition_definition text,
  p_steps jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_template_id uuid;
  v_step jsonb;
  v_sequence integer := 0;
begin
  if public.current_user_role() not in ('system_administrator', 'planning_manager', 'factory_manager') then raise exception 'You are not authorized to create workflow templates'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'Workflow name is required'; end if;
  if p_workflow_structure not in ('sequential', 'parallel', 'conditional') then raise exception 'Invalid workflow structure'; end if;
  if p_workflow_structure = 'conditional' and (p_condition_definition is null or length(trim(p_condition_definition)) = 0) then raise exception 'Conditional workflows require a condition definition'; end if;
  if jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) < 1 then raise exception 'At least one workflow step is required'; end if;

  insert into public.workflow_templates (name, description, factory_id, workflow_structure, condition_definition, created_by)
  values (trim(p_name), nullif(trim(p_description), ''), p_factory_id, p_workflow_structure, nullif(trim(p_condition_definition), ''), auth.uid())
  returning id into v_template_id;

  for v_step in select value from jsonb_array_elements(p_steps) loop
    v_sequence := v_sequence + 1;
    insert into public.workflow_steps (workflow_template_id, department_id, title, description, sequence_number, is_required)
    values (v_template_id, (v_step->>'department_id')::uuid, trim(v_step->>'title'), nullif(trim(v_step->>'description'), ''), v_sequence, coalesce((v_step->>'is_required')::boolean, true));
  end loop;
  return v_template_id;
end;
$$;

revoke execute on function public.create_workflow_template_v2(text, text, uuid, text, text, jsonb) from public;
grant execute on function public.create_workflow_template_v2(text, text, uuid, text, text, jsonb) to authenticated;
