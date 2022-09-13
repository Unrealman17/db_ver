CREATE MATERIALIZED VIEW reclada.v_class_lite
AS
WITH RECURSIVE
objects_schemas AS (
    SELECT  obj.id,
            obj.GUID AS obj_id,
            obj.attributes->>'forClass' AS for_class,
            obj.created_time,
            obj.attributes,
            obj.active
	    FROM reclada.object obj
   	    WHERE class = reclada_object.get_jsonschema_guid()
),
paths_to_default AS
(
    SELECT   ('{'||row_attrs_base.key||'}')::text[] AS path_head,
             row_attrs_base.value AS path_tail,
             o.obj_id
        FROM objects_schemas o
        CROSS JOIN LATERAL jsonb_each(o.attributes) row_attrs_base
        WHERE jsonb_typeof(row_attrs_base.value) = 'object'
            AND o.attributes::text LIKE '%default%'
    UNION ALL
    SELECT   p.path_head || row_attrs_rec.key AS path_head, -- {schema,properties,nested_1,nested_2,nested_3}
             row_attrs_rec.value AS path_tail, ---{"type": "integer", "default": 100}
             p.obj_id
       FROM paths_to_default p
       CROSS JOIN LATERAL jsonb_each(p.path_tail) row_attrs_rec
       WHERE jsonb_typeof(row_attrs_rec.value) = 'object'
),
tmp AS
(
    SELECT   reclada.jsonb_deep_set(
                '{}'::jsonb,
                t.path_head[array_position(t.path_head, 'properties') + 1 : ],
                t.path_tail->'default')
             AS default_jsonb,
             t.obj_id
        FROM paths_to_default t
        WHERE t.path_tail->'default' IS NOT NULL
),
default_field AS
(
    SELECT   format('{"attributes": %s}',
                    reclada.jsonb_object_agg(default_jsonb))::jsonb
             AS default_value,
             obj_id
        FROM tmp
        GROUP BY obj_id
)

SELECT
        obj.id,
        obj.obj_id,
        obj.for_class,
        obj.created_time,
        obj.attributes,
        obj.active,
        def.default_value
    FROM objects_schemas obj
        LEFT JOIN default_field def
        ON def.obj_id = obj.obj_id;


ANALYZE reclada.v_class_lite;

--SELECT * FROM reclada.v_class_lite;
--SELECT * FROM reclada.v_active_object
