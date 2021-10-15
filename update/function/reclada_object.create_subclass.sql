/*
 * Function reclada_object.create_subclass creates subclass.
 * A jsonb object with the following parameters is required.
 * Required parameters:
 *  class - the name of parent class
 *  attributes - the attributes of objects of the class. The field contains:
 *      forClass - the name of class to create
 *      schema - the schema for the class
 */

DROP FUNCTION IF EXISTS reclada_object.create_subclass;
CREATE OR REPLACE FUNCTION reclada_object.create_subclass(data jsonb)
RETURNS VOID AS $$
DECLARE
    class           text;
    new_class       text;
    attrs           jsonb;
    class_schema    jsonb;
    version_         integer;

BEGIN

    class := data->>'class';
    IF (class IS NULL) THEN
        RAISE EXCEPTION 'The reclada object class is not specified';
    END IF;

    attrs := data->'attributes';
    IF (attrs IS NULL) THEN
        RAISE EXCEPTION 'The reclada object must have attributes';
    END IF;

    new_class = attrs->>'newClass';

    SELECT reclada_object.get_schema(class) INTO class_schema;

    IF (class_schema IS NULL) THEN
        RAISE EXCEPTION 'No json schema available for %', class;
    END IF;

    SELECT max(version) + 1
    FROM reclada.v_class_lite v
    WHERE v.for_class = new_class
    INTO version_;

    version_ := coalesce(version_,1);
    class_schema := class_schema->'attributes'->'schema';

    PERFORM reclada_object.create(format('{
        "class": "jsonschema",
        "attributes": {
            "forClass": "%s",
            "version": "%s",
            "schema": {
                "type": "object",
                "properties": %s,
                "required": %s
            }
        }
    }',
    new_class,
    version_,
    (class_schema->'properties') || (attrs->'properties'),
    (SELECT jsonb_agg(el) FROM (
        SELECT DISTINCT pg_catalog.jsonb_array_elements(
            (class_schema -> 'required') || (attrs -> 'required')
        ) el) arr)
    )::jsonb);

    IF ( jsonb_typeof(attrs->'properties'->'dupChecking') = 'array' ) THEN
        for _uniFields IN (
            SELECT jsonb_array_elements(attrs->'properties'->'dupChecking')->'uniFields'
        ) LOOP
            IF ( jsonb_typeof(_uniFields) = 'array' ) THEN
                SELECT
                    get_unifield_index_name( array_agg(f ORDER BY f)) AS idx_name, 
                    string_agg('(attributes ->> ''' || f || ''')','||' ORDER BY f) AS fields_list
                FROM (
                    SELECT jsonb_array_elements_text (_uniFields::jsonb) f
                ) a
                    INTO _idx_name, _f_list;
                SELECT count(*) 
                FROM pg_catalog.pg_indexes pi2 
                WHERE schemaname ='reclada' AND tablename ='object' AND indexname =_idx_name
                    INTO _idx_cnt;
                IF (_idx_cnt = 0 ) THEN
                    EXECUTE E'CREATE INDEX ' || _idx_name || ' ON reclada.object USING HASH ((' || _f_list || '))';
                END IF;
            END IF;
        END LOOP;
        PERFORM reclada_object.refresh_mv('uniFields');
    END IF;

END;
$$ LANGUAGE PLPGSQL VOLATILE;

