-- Exposed SECURITY DEFINER functions must not be callable by anonymous/public roles.

revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;
revoke all on function public.enqueue_notification_email() from public;
