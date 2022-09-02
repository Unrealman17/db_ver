-- version = 51
/*
    you can use "\i 'function/reclada_object.get_schema.sql'"
    to run text script of functions
*/

DROP TABLE reclada.unique_object_reclada_object;
DROP TABLE reclada.unique_object;
DROP TABLE reclada.field;
DROP FUNCTION reclada.update_unique_object;

\i 'function/reclada_object.create.sql'
\i 'function/reclada_object.update.sql'
\i 'function/reclada_object.list.sql'
\i 'function/reclada_object.get_parent_guid.sql'
