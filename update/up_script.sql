-- version = 2
/*
  you can use "\i 'function/reclada_object.get_schema.sql'"
  to run text script of functions
*/

delete from reclada.object where transaction_id = 2;

\i 'function/reclada_object.create_subclass.sql'
