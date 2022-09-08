/*
 * Function reclada_object.list returns the list of objects with specified fields.
 * Also it is possible to get the number of objects. For that two arguments are required for input:
 * 1. the jsonb object with information about specified fields with the following parameters is required
 * 2. boolean argument is optional
 *    If it is true then output is jsonb like this {"objects": [<list of objects>], "number": <number of objects>, "last_change": <greatest timestamp of selection>}.
 *    If it is false (default value) then output is jsonb like this [<list of objects>].
 * Required parameters for the jsonb object:
 *  class - the class of objects
 * Optional parameters:
 *  attributes - the attributes of objects (can be empty)
 *  GUID - the identifier of the objects. All object's GUID of the class are taken by default.
 *  transactionID - object's transaction number
 *  orderBy - list of jsons in the form of {"field": "field_name", "order": <"ASC"/"DESC">}.
 *      field - required value with name of property to order by
 *      order - optional value of the order; default is "ASC". Sorted by id in ascending order by default
 *  limit - the number or string "ALL", no more than this many objects will be returned. Default limit value is 500.
 *  offset - the number to skip this many objects before beginning to return objects. Default offset value is 0.
 * It is possible to pass a certain operator and object for each field. Also it is possible to pass several conditions for one field.
 * Function reclada_object.list uses auxiliary functions get_query_condition, cast_jsonb_to_postgres, jsonb_to_text, get_condition_array.
 * Function supports:
 * 1. Comparison Operators
 * elem1   >, <, <=, >=, =, !=   elem2
 * elem1 < x < elem2 -- like two conditions
 * 2. Pattern Matching
 * str1   LIKE / NOT LIKE    str2
 * str    SIMILAR TO         exp
 * str    ~ ~* !~ !~*        exp
 * 3. Array Operators
 * elem   <@   list
 * list1   =, !=, <, >, <=, >=, @>, <@  list2
 * Examples:
 *   1. Input:
 *   {
 *   "class": "class_name",
 *   "GUID": "id_1",
 *   "attributes":
 *       {
 *       "name": {"operator": "LIKE", "object": "%test%"},
 *       "numericField": {"operator": "!=", "object": 123}
 *       },
 *   "orderBy": [{"field": "attributes, name", "order": "ASC"}],
 *   }::jsonb
 *   2. Input:
 *   {
 *   "class": "class_name",
 *   "GUID": {"operator": "<@", "object": ["id_1", "id_2", "id_3"]},
 *   "attributes":
 *       {
 *       "tags":{"operator": "@>", "object": ["value1", "value2"]},
 *       "numericField": [{"operator": ">", "object": num1}, {"operator": "<", "object": num2}]
 *       },
 *   "orderBy": [{"field": "id", "order": "DESC"}],
 *   "limit": 5,
 *   "offset": 2
 *   }::jsonb
 *
Comparison Operators
    >
    <
    <=
    >= 
    = 
        {
            "operator": "=",
            "value": 
            [
                "{class}", 
                "DataSet"
            ]
        }
        another:
        {
            "operator": "=",
            "value": 
            [
                "{attributes,dataSources}", 
                [
                    "2033ef08-a89f-4789-91f5-bcf02533963d", 
                    "a3a1b54e-74b8-4a95-a818-8e5337d264c0"
                ]
            ]
        }
    !=
Logical:
    AND
    OR
    NOT
    # - XOR
Other:
    LIKE / ~ / !~ / ~* / !~* / SIMILAR TO (second operand must be string) 
        {
            "operator":"LIKE",
            "value":["{class}","rev%"]
        }
    NOT LIKE (second operand must be string)
        {
            "operator":"NOT LIKE",
            "value":["{class}","rev%"]
        }
        equivalent:
        {
            "operator":"NOT",
            "value":
            [
                {
                    "operator":"LIKE",
                    "value":["{class}","rev%"]
                }
            ]
        }
    IS (second operand must be NULL)
        { 
            "operator":"IS", 
            "value":
            [
                "{class}",
                null
            ]
        }
    IS NOT (second operand must be NULL)
        { 
            "operator":"IS NOT", 
            "value":
            [
                "{class}",
                null
            ]
        }
        equivalent:
        { 
            "operator":"NOT", 
            "value":
            [
                { 
                    "operator":"IS", 
                    "value":
                    [
                        "{class}",
                        null
                    ]
                }
            ]
        }
        note: not equivalent:
        { 
            "operator":"IS", 
            "value":
            [
                "{class}",
                 {
                    "operator":"NOT",
                    "value":
                    [
                        null
                    ]
                }
            ]
        }
    IN (second operand must be ",")
        {
            "operator":"in",
            "value":
            [
                "{attributes,num}",
                { 
                    "operator":",", 
                    "value":
                    [
                        2,3
                    ]
                }
            ]
        }
    , using only with IN (example before)
    || - concatenation of strings, operands must be string
        { 
            "operator":"=", 
            "value":
            [
                "{attributes,forClass}",
                { 
                    "operator":"||", 
                    "value":
                    [
                        "Pa",
                        "{attributes,forClass}"
                    ]
                }
            ]
        }
        another:
        { 
            "operator":"=", 
            "value":
            [
                "{attributes,forClass}",
                { 
                    "operator":"||", 
                    "value":
                    [
                        "Pa",
                        "g",
                        "e"
                    ]
                }
            ]
        }
    + - addition of numbers, operands must be number
        { 
            "operator":"=", 
            "value":
            [
                "{transactionID}",
                { 
                    "operator":"+", 
                    "value":
                    [
                        4,
                        5
                    ]
                }
            ]
        }
        another:
        { 
            "operator":"=", 
            "value":
            [
                "{transactionID}",
                { 
                    "operator":"+", 
                    "value":
                    [
                        "{transactionID}",
                        1,
                        -1
                    ]
                }
            ]
        }

*/

DROP FUNCTION IF EXISTS reclada_object.list;
CREATE OR REPLACE FUNCTION reclada_object.list(
    data jsonb, 
    gui boolean default false,
    ver text default '1' 
)
RETURNS jsonb AS $$
DECLARE
    _f_name TEXT = 'reclada_object.list';
    _class              text;
    attrs               jsonb;
    order_by_jsonb      jsonb;
    order_by            text;
    limit_              text;
    offset_             text;
    query_conditions    text;
    number_of_objects   int;
    objects             jsonb;
    res                 jsonb;
    _exec_text          text;
    _pre_query          text;
    _from               text;
    class_uuid          uuid;
    last_change         text;
    tran_id             bigint;
    _filter             jsonb;
    _object_display     jsonb;
    _order_row          jsonb;
BEGIN

    perform reclada.validate_json(data, _f_name);

    tran_id := (data->>'transactionID')::bigint;
    _class := data->>'class';
    _filter = data->'filter';

    order_by_jsonb := data->'orderBy';
    IF ((order_by_jsonb IS NULL) OR
        (order_by_jsonb = 'null'::jsonb) OR
        (order_by_jsonb = '[]'::jsonb)) THEN
        order_by_jsonb := '[{"field": "id", "order": "ASC"}]'::jsonb;
    END IF;
    
    SELECT string_agg(
        format(
            E'obj.data#>''{%s}'' %s', 
            case ver
                when '2'
                    then REPLACE(REPLACE(T.value->>'field','{', '"{' ),'}', '}"' )
                else
                    T.value->>'field'
            end,
            COALESCE(T.value->>'order', 'ASC')),
        ' , ')
        FROM jsonb_array_elements(order_by_jsonb) T
        INTO order_by;

    limit_ := data->>'limit';
    IF (limit_ IS NULL) THEN
        limit_ := 500;
    END IF;

    offset_ := data->>'offset';
    IF (offset_ IS NULL) THEN
        offset_ := 0;
    END IF;
    
    IF (_filter IS NOT NULL) THEN
        query_conditions := reclada_object.get_query_condition_filter(_filter);
    ELSEIF ver = '1' then
        class_uuid := reclada.try_cast_uuid(_class);

        IF (class_uuid IS NULL) THEN
            SELECT v.obj_id
                FROM reclada.v_class v
                    WHERE _class = v.for_class
                    ORDER BY v.version DESC
                    limit 1 
            INTO class_uuid;
            IF (class_uuid IS NULL) THEN
                perform reclada.raise_exception(
                        format('Class not found: %s', _class),
                        _f_name
                    );
            END IF;
        end if;

        attrs := data->'attributes' || '{}'::jsonb;

        SELECT
            string_agg(
                format(
                    E'(%s)',
                    condition
                ),
                ' AND '
            )
            FROM (
                SELECT
                    format('obj.class_name = ''%s''', _class) AS condition
                        where _class is not null
                UNION
                    SELECT format('obj.class = ''%s''', class_uuid) AS condition
                        where class_uuid is not null
                            and _class is null
                UNION
                    SELECT format('obj.transaction_id = %s', tran_id) AS condition
                        where tran_id is not null
                UNION
                    SELECT CASE
                            WHEN jsonb_typeof(data->'GUID') = 'array' THEN
                            (
                                SELECT string_agg
                                    (
                                        format(
                                            E'(%s)',
                                            reclada_object.get_query_condition(cond, E'data->''GUID''') -- TODO: change data->'GUID' to obj_id(GUID)
                                        ),
                                        ' AND '
                                    )
                                    FROM jsonb_array_elements(data->'GUID') AS cond
                            )
                            ELSE reclada_object.get_query_condition(data->'GUID', E'data->''GUID''') -- TODO: change data->'GUID' to obj_id(GUID)
                        END AS condition
                    WHERE coalesce(data->'GUID','null'::jsonb) != 'null'::jsonb
                UNION
                SELECT
                    CASE
                        WHEN jsonb_typeof(value) = 'array'
                            THEN
                                (
                                    SELECT string_agg
                                        (
                                            format
                                            (
                                                E'(%s)',
                                                reclada_object.get_query_condition(cond, format(E'attrs->%L', key))
                                            ),
                                            ' AND '
                                        )
                                        FROM jsonb_array_elements(value) AS cond
                                )
                        ELSE reclada_object.get_query_condition(value, format(E'attrs->%L', key))
                    END AS condition
                FROM jsonb_each(attrs)
                WHERE attrs != ('{}'::jsonb)
            ) conds
        INTO query_conditions;
    END IF;
    -- TODO: add ELSE

    _pre_query := '';
    _from := 'reclada.v_active_object AS obj
                        WHERE #@#@#where#@#@#';
    _from := REPLACE(_from, '#@#@#where#@#@#', query_conditions  );

    _exec_text := _pre_query ||
                'SELECT to_jsonb(array_agg(t.data))
                    FROM 
                    (
                        SELECT reclada.jsonb_merge(obj.data, obj.default_value) AS data
                            FROM '
                            || _from
                            || ' 
                            ORDER BY #@#@#orderby#@#@#
                                OFFSET #@#@#offset#@#@#
                                LIMIT #@#@#limit#@#@#
                    ) AS t';
    _exec_text := REPLACE(_exec_text, '#@#@#orderby#@#@#'  , order_by          );
    _exec_text := REPLACE(_exec_text, '#@#@#offset#@#@#'   , offset_           );
    _exec_text := REPLACE(_exec_text, '#@#@#limit#@#@#'    , limit_            );
    -- RAISE NOTICE 'conds: %', _exec_text;

    EXECUTE _exec_text
        INTO objects;
    objects := coalesce(objects,'[]'::jsonb);
    IF gui THEN

        _exec_text := '
            SELECT  COUNT(1),
                    TO_CHAR(
                        MAX(
                            GREATEST(
                                obj.created_time, 
                                (
                                    SELECT  TO_TIMESTAMP(
                                                MAX(date_time),
                                                ''YYYY-MM-DD hh24:mi:ss.US TZH''
                                            )
                                        FROM reclada.v_revision vr
                                            WHERE vr.obj_id = UUID(obj.attrs ->>''revision'')
                                )
                            )
                        ),
                        ''YYYY-MM-DD hh24:mi:ss.MS TZH''
                    )
                    FROM reclada.v_active_object obj 
                        where #@#@#where#@#@#';

        _exec_text := REPLACE(_exec_text, '#@#@#where#@#@#', query_conditions  );
        -- raise notice '%',_exec_text;
        EXECUTE _exec_text
            INTO number_of_objects, last_change;
        
        IF _object_display IS NOT NULL then
            res := jsonb_build_object(
                    'lastСhange', last_change,    
                    'number', number_of_objects,
                    'objects', objects,
                    'display', _object_display
                );
        ELSE
            res := jsonb_build_object(
                    'lastСhange', last_change,    
                    'number', number_of_objects,
                    'objects', objects
            );
        end if;
    ELSE
        
        res := objects;
    END IF;

    RETURN res;


END;
$$ LANGUAGE PLPGSQL VOLATILE;