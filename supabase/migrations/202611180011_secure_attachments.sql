-- Secure private attachments for orders, tasks and handovers.

insert into storage.buckets (id, name, public)
values ('catch-pass-attachments', 'catch-pass-attachments', false)
on conflict (id) do update set public = false;

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  file_size bigint check (file_size is null or file_size >= 0),
  order_id uuid references public.orders(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete cascade,
  handover_id uuid references public.handovers(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint attachment_parent_required check (order_id is not null or task_id is not null or handover_id is not null)
);

create index attachments_order_id_idx on public.attachments(order_id);
create index attachments_task_id_idx on public.attachments(task_id);
alter table public.attachments enable row level security;

create policy "Authorized users view attachments" on public.attachments for select to authenticated using (
  uploaded_by = auth.uid() or (order_id is not null and exists (select 1 from public.orders o where o.id = attachments.order_id)) or (task_id is not null and exists (select 1 from public.tasks t where t.id = attachments.task_id)) or (handover_id is not null and exists (select 1 from public.handovers h where h.id = attachments.handover_id))
);
create policy "Authorized users upload attachments" on public.attachments for insert to authenticated with check (uploaded_by = auth.uid());
create policy "Uploader deletes attachments" on public.attachments for delete to authenticated using (uploaded_by = auth.uid() or public.current_user_role() = 'system_administrator');

create policy "Authenticated users upload private files" on storage.objects for insert to authenticated with check (bucket_id = 'catch-pass-attachments' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "Authorized users read private files" on storage.objects for select to authenticated using (bucket_id = 'catch-pass-attachments' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "Uploaders delete private files" on storage.objects for delete to authenticated using (bucket_id = 'catch-pass-attachments' and (storage.foldername(name))[1] = (select auth.uid()::text));

grant select, insert, delete on public.attachments to authenticated;
