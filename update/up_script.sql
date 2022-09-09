-- version = 2
/*
  you can use "\i 'function/reclada_object.get_schema.sql'"
  to run text script of functions
*/


CREATE table public.num(id int, val text);

\i 'view/public.v_cat.sql'
\i 'view/public.v_green_cat.sql'

