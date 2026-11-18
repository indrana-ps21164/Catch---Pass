-- Explicit Data API grants for browser-authenticated access. RLS remains mandatory.

grant select on public.factories, public.departments, public.profiles, public.employee_factory_access, public.employee_department_access to authenticated;
grant select, insert, update on public.orders, public.order_items to authenticated;
grant select on public.workflow_templates, public.workflow_steps, public.order_workflows, public.tasks, public.task_dependencies, public.task_assignments, public.handovers, public.handover_recipients, public.task_history, public.notifications, public.audit_logs, public.attachments, public.shipments, public.shipment_items to authenticated;
