DROP FUNCTION IF EXISTS reclada.validate_json_schema;
CREATE OR REPLACE FUNCTION reclada.validate_json_schema
(
    _data       jsonb
)
RETURNS TABLE
(
    schema_obj  jsonb , 
    attributes  jsonb ,
    class_name  text  ,
    class_guid  uuid
)
AS $$
DECLARE
    _schema_obj     jsonb;
    _valid_schema   jsonb;
    _attrs          jsonb;
    _class          text ;
    _class_name     text ;
    _class_guid     uuid ;
    _f_name         text = 'reclada.validate_json_schema';
BEGIN

    -- perform reclada.raise_notice(_data#>>'{}');
    _class := _data->>'class';

    IF (_class IS NULL) THEN
        perform reclada.raise_exception('The reclada object class is not specified',_f_name);
    END IF;

    SELECT reclada_object.get_schema(_class) 
        INTO _schema_obj;

    IF (_schema_obj IS NULL) THEN
        perform reclada.raise_exception('No json schema available for ' || _class_name);
    END IF;

    _class_guid := (_schema_obj->>'GUID')::uuid;

    SELECT  v.for_class, 
            validation_schema
        FROM reclada.v_class v
            WHERE _class_guid = v.obj_id
        INTO    _class_name, 
                _valid_schema;

    _attrs := _data->'attributes';
    IF (_attrs IS NULL) THEN
        perform reclada.raise_exception('The reclada object must have attributes',_f_name);
    END IF;

    IF (NOT(public.validate_json_schema(_valid_schema, _attrs))) THEN
        perform reclada.raise_exception(format('JSON invalid: %s, schema: %s', 
                                                _attrs #>> '{}'   , 
                                                _valid_schema #>> '{}'
                                            ),
                                        _f_name);
    END IF;

    RETURN QUERY
        SELECT  _schema_obj , 
                _attrs      , 
                _class_name , 
                _class_guid  ;
END;
$$ LANGUAGE PLPGSQL STABLE;