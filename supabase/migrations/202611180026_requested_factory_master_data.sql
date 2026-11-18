-- Requested baseline factory master records for Order Creation.
-- This is intentional configuration data requested by the workspace owner,
-- not demo orders, users, tasks, or dashboard fixtures.

insert into public.factories (name, code)
select source.name, source.code
from (values
  ('CM', 'CM'),
  ('VCO', 'VCO'),
  ('Cream', 'CREAM'),
  ('Recart', 'RECART'),
  ('Flour', 'FLOUR'),
  ('Chip', 'CHIP'),
  ('Amino', 'AMINO'),
  ('Sugar', 'SUGAR'),
  ('Other', 'OTHER')
) as source(name, code)
where not exists (
  select 1 from public.factories existing
  where existing.code = source.code or existing.name = source.name
);
