-- Notifications are written by the validated server-side transaction, not arbitrary browser inserts.
drop policy if exists "Authenticated users create notifications" on public.notifications;
