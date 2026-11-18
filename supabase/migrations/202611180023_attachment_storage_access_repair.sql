-- Allow authorized participants to download private files attached to records they can read.

drop policy if exists "Authorized users read private files" on storage.objects;

create policy "Authorized users read private files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'catch-pass-attachments'
    and exists (
      select 1
      from public.attachments a
      where a.storage_path = storage.objects.name
        and (
          a.uploaded_by = auth.uid()
          or (a.order_id is not null and exists (select 1 from public.orders o where o.id = a.order_id))
          or (a.task_id is not null and exists (select 1 from public.tasks t where t.id = a.task_id))
          or (a.handover_id is not null and exists (select 1 from public.handovers h where h.id = a.handover_id))
        )
    )
  );
