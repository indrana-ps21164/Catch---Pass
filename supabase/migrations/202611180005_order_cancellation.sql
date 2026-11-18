-- Phase 2: preserve cancellation reason on orders.

alter table public.orders add column if not exists cancellation_reason text;
alter table public.orders add constraint cancellation_reason_required check (status <> 'cancelled' or length(trim(cancellation_reason)) > 0);
