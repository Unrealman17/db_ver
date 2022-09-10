-- version = 3
/*
  you can use "\i 'function/reclada_object.get_schema.sql'"
  to run text script of functions
*/

alter table public.num add COLUMN val2 text;

drop view public.v_green_cat;

\i 'view/public.v_cat.sql'
\i 'view/public.v_green_cat.sql'


\i 'function/dev.downgrade_component.sql'
