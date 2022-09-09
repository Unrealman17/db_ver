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
\i 'function/reclada_object.refresh_mv.sql'
\i 'function/reclada.create_revision.sql'


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

drop SCHEMA reclada_storage;

drop SCHEMA reclada_notification CASCADE;

drop SCHEMA reclada_user CASCADE;

drop SCHEMA reclada_revision CASCADE;

drop FUNCTION reclada.load_staging;

DROP FUNCTION reclada_object.list_add;

DROP FUNCTION reclada_object.list_drop;

DROP FUNCTION reclada_object.list_related;

DROP FUNCTION reclada.get_unifield_index_name;

DROP FUNCTION reclada.get_transaction_id_for_import;

DROP FUNCTION reclada.rollback_import;

DROP FUNCTION reclada.get_children;

DROP FUNCTION reclada_object.get_parent_guid;

DROP VIEW reclada.v_parent_field;

DROP FUNCTION reclada_object.get_query_condition_filter;

drop VIEW reclada.v_filter_mapping;

drop VIEW reclada.v_filter_inner_operator;

drop VIEW reclada.v_filter_between;

DROP VIEW reclada.v_filter_available_operator;

drop OPERATOR reclada.##(boolean,boolean);

drop FUNCTION reclada.xor;

DROP FUNCTION reclada_object.update_json_by_guid;

DROP FUNCTION reclada_object.update_json;

DROP FUNCTION reclada_object.remove_parent_guid;

DROP FUNCTION reclada_object.parse_filter;

DROP FUNCTION reclada_object.merge;

DROP FUNCTION reclada_object.is_equal;

DROP FUNCTION reclada.random_string;

DROP FUNCTION reclada_object.get_transaction_id;

drop TABLE reclada.auth_setting;

drop TABLE reclada.draft;

drop MATERIALIZED VIEW reclada.v_object_unifields;

drop TYPE reclada.dp_bhvr;

DROP FUNCTION reclada.try_cast_int;

DROP FUNCTION reclada_object.create_job;

DROP FUNCTION reclada_object.explode_jsonb;

DROP INDEX reclada.height_index_v47;

DROP INDEX reclada.colspan_index_v47;

DROP INDEX reclada.column_index_v47;

DROP INDEX reclada.environment_index_v47;

DROP INDEX reclada.event_index_v47;

DROP INDEX reclada.left_index_v47;

DROP INDEX reclada.nexttask_index_v47;

DROP INDEX reclada.number_index_v47;

DROP INDEX reclada.object_index_v47;

DROP INDEX reclada.row_index_v47;

DROP INDEX reclada.runner_type_index;

DROP INDEX reclada.subject_index_v47;

DROP INDEX reclada.task_index_v47;

DROP INDEX reclada.tasks_index_v47;

DROP INDEX reclada.top_index_v47;

DROP INDEX reclada.tranid_index_v47;

DROP INDEX reclada.triggers_index_v47;

DROP INDEX reclada.width_index_v47;

DROP INDEX reclada.rowspan_index_v47;






