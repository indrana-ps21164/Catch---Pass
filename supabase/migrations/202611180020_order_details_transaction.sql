-- Extend atomic draft creation to include customer/internal remarks while retaining multi-line orders.

create or replace function public.create_draft_order_with_details(
  p_customer_name text,
  p_customer_reference text,
  p_factory_id uuid,
  p_required_delivery_date date,
  p_priority public.order_priority,
  p_customer_remarks text,
  p_internal_remarks text,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_item jsonb;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 then
    raise exception 'At least one product line is required';
  end if;

  insert into public.orders (customer_name, customer_reference, factory_id, required_delivery_date, priority, customer_remarks, internal_remarks, created_by)
  values (trim(p_customer_name), nullif(trim(p_customer_reference), ''), p_factory_id, p_required_delivery_date, p_priority, nullif(trim(p_customer_remarks), ''), nullif(trim(p_internal_remarks), ''), auth.uid())
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (order_id, product_code, product_description, quantity, unit_of_measurement, remarks)
    values (v_order_id, trim(v_item->>'product_code'), trim(v_item->>'product_description'), (v_item->>'quantity')::numeric, trim(v_item->>'unit_of_measurement'), nullif(trim(v_item->>'remarks'), ''));
  end loop;

  return v_order_id;
end;
$$;

revoke execute on function public.create_draft_order_with_details(text, text, uuid, date, public.order_priority, text, text, jsonb) from public;
grant execute on function public.create_draft_order_with_details(text, text, uuid, date, public.order_priority, text, text, jsonb) to authenticated;
