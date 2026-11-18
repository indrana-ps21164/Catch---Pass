-- Reliable email notification outbox. Email delivery never blocks in-app notifications.

create table public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  recipient_email text not null,
  subject text not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'sent', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(notification_id)
);

create index email_outbox_pending_idx on public.email_outbox(status, next_attempt_at);
alter table public.email_outbox enable row level security;

create or replace function public.enqueue_notification_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email from public.profiles where id = new.recipient_id and is_active = true;
  if v_email is not null then
    insert into public.email_outbox (notification_id, recipient_email, subject)
    values (new.id, v_email, new.title)
    on conflict (notification_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_email_outbox_trigger on public.notifications;
create trigger notifications_email_outbox_trigger after insert on public.notifications for each row execute function public.enqueue_notification_email();

revoke all on public.email_outbox from anon, authenticated;
