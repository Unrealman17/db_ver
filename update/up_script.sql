-- version = 2
/*
    you can use "\i 'function/reclada_object.get_schema.sql'"
    to run text script of functions
*/


\i 'function/reclada_object.create.sql'
\i 'function/reclada_object.create_subclass.sql'
\i 'function/reclada_object.delete.sql'
\i 'function/reclada_object.list.sql'
\i 'function/reclada_object.update.sql'
\i 'function/dev.finish_install_component.sql'
\i 'view/reclada.v_cat.sql'

DROP TRIGGER load_staging ON reclada.staging;

drop table reclada.staging;

drop VIEW reclada.v_ui_active_object;

drop VIEW reclada.v_trigger;

DROP FUNCTION reclada_object.perform_trigger_function;

DROP FUNCTION reclada_object.object_insert;

DROP VIEW reclada.v_db_trigger_function;

drop VIEW reclada.v_import_info;

drop VIEW reclada.v_task;

DROP FUNCTION reclada_object.need_flat;

drop VIEW reclada.v_object_display;

DROP FUNCTION reclada.get_duplicates;

DROP VIEW reclada.v_get_duplicates_query;

drop VIEW reclada.v_default_display;

drop SCHEMA api CASCADE;

drop SCHEMA reclada_notification CASCADE;

drop FUNCTION reclada.load_staging;

DROP FUNCTION reclada_object.list_add;

DROP FUNCTION reclada_object.list_drop;

DROP FUNCTION reclada_object.list_related;

DROP FUNCTION reclada.get_unifield_index_name;

DROP FUNCTION reclada.get_transaction_id_for_import;

DROP FUNCTION reclada.rollback_import;
