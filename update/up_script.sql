-- version = 46
/*
    you can use "\i 'function/reclada_object.get_schema.sql'"
    to run text script of functions
*/


--------------default----------------

\i 'function/reclada_object.get_guid_for_class.sql'
\i 'function/reclada_object.delete.sql'
\i 'function/reclada_object.need_flat.sql'

UPDATE reclada.object
SET attributes = '{
    "schema": {
        "id": "expr",
        "type": "object",
        "required": [
          "value",
          "operator"
        ],
        "properties": {
          "value": {
            "type": "array",
            "items": {
              "anyOf": [
                {
                  "type": "string"
                },
                {
                  "type": "null"
                },
                {
                  "type": "number"
                },
                {
                  "$ref": "expr"
                },
                {
                  "type": "boolean"
                },
                {
                  "type": "array",
                  "items": {
                    "anyOf": [
                      {
                        "type": "string"
                      },
                      {
                        "type": "number"
                      }
                    ]
                  }
                }
              ]
            },
            "minItems": 1
          },
          "operator": {
            "type": "string"
          }
        }
      },
    "function": "reclada_object.get_query_condition_filter"
}'::jsonb
WHERE attributes->>'function' = 'reclada_object.get_query_condition_filter';

UPDATE reclada.object
SET attributes = (SELECT jsonb_set(attributes, '{schema, properties}', attributes #> '{schema, properties}' || '{"disable": {"type": "boolean", "default": false}}'::jsonb))
WHERE class IN (SELECT reclada_object.get_guid_for_class('jsonschema'))
AND attributes->>'forClass' != 'ObjectDisplay'
AND attributes->>'forClass' != 'jsonschema';


\i 'function/reclada_object.get_query_condition_filter.sql'
\i 'function/reclada_object.create_subclass.sql'

--DROP VIEW IF EXISTS reclada.v_unifields_idx_cnt;
DROP VIEW IF EXISTS reclada.v_unifields_pivoted;
DROP MATERIALIZED VIEW IF EXISTS reclada.v_object_unifields;
DROP VIEW IF EXISTS reclada.v_parent_field;
DROP VIEW IF EXISTS reclada.v_class;
DROP VIEW IF EXISTS reclada.v_import_info;
DROP VIEW IF EXISTS reclada.v_revision;
DROP VIEW IF EXISTS reclada.v_task;
DROP VIEW IF EXISTS reclada.v_ui_active_object;
DROP VIEW IF EXISTS reclada.v_dto_json_schema;
DROP VIEW IF EXISTS reclada.v_active_object;
DROP VIEW IF EXISTS reclada.v_object;
DROP MATERIALIZED VIEW IF EXISTS reclada.v_class_lite;
DROP MATERIALIZED VIEW IF EXISTS reclada.v_user;
DROP MATERIALIZED VIEW IF EXISTS reclada.v_object_status;
DROP VIEW IF EXISTS reclada.v_object_display;

\i 'view/reclada.v_object_display.sql'
\i 'function/reclada_object.built_nested_jsonb.sql'
\i 'view/reclada.v_class_lite.sql'
\i 'view/reclada.v_object_status.sql'
\i 'view/reclada.v_user.sql'
\i 'view/reclada.v_object.sql'
\i 'view/reclada.v_active_object.sql'
\i 'view/reclada.v_dto_json_schema.sql'
\i 'view/reclada.v_ui_active_object.sql'
\i 'view/reclada.v_task.sql'
\i 'view/reclada.v_revision.sql'
\i 'view/reclada.v_import_info.sql'
\i 'view/reclada.v_class.sql'
\i 'view/reclada.v_parent_field.sql'
\i 'view/reclada.v_object_unifields.sql'
\i 'view/reclada.v_unifields_pivoted.sql'



