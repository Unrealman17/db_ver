/*
 * Function reclada_object.create_subclass creates subclass.
 * A jsonb object with the following parameters is required.
 * Required parameters:
 *  _class_list - the name of parent _class_list
 *  attributes - the attributes of objects of the _class_list. The field contains:
 *      forClass - the name of _class_list to create
 *      schema - the schema for the _class_list
 */

DROP FUNCTION IF EXISTS reclada_object.create_subclass;
CREATE OR REPLACE FUNCTION reclada_object.create_subclass(_data jsonb)
RETURNS jsonb AS $$
DECLARE
    _res            jsonb = '{}'::jsonb;
    _new_class      text;
    _f_name         text = 'reclada_object.create_subclass';
    _create_obj     jsonb;
    _component_guid uuid;
    _obj_guid       uuid;
    _row_count      int;
    _schema         jsonb = '{}'::jsonb;
	_tran_id        bigint;
BEGIN

    _obj_guid := COALESCE((_data->>'GUID')::uuid, public.uuid_generate_v4());
    _tran_id  := COALESCE((_data->>'transactionID')::bigint, reclada.get_transaction_id());
    _new_class  := _data->>'class';
    _schema     := _data->'schema';

    IF (_schema IS NULL) THEN
        PERFORM reclada.raise_exception('The schema is required',_f_name);
    END IF;

    SELECT guid 
        FROM dev.component 
        INTO _component_guid;

    if _component_guid is not null then
        update dev.component_object
            set status = 'ok'
            where status = 'need to check'
                and _new_class  =          data #>> '{attributes,forClass}'
                and _schema     = COALESCE(data #>  '{attributes,schema}','{}'::jsonb);

        GET DIAGNOSTICS _row_count := ROW_COUNT;
        if _row_count > 1 then
            perform reclada.raise_exception('Can not match component objects',_f_name);
        elsif _row_count = 1 then
            return ('{"message": "Installing component, create_subclass('
                        || _new_class
                        || '), status = ''ok''"}'
                    )::jsonb;
        end if;

        -- upgrade jsonschema
        with u as (
            update dev.component_object
                set status = 'delete'
                where status = 'need to check'
                    and _new_class  = data #>> '{attributes,forClass}'
                RETURNING 1 as v
        )
        insert into dev.component_object( data, status  )
            select _data, 'create_subclass'
                from u;

        GET DIAGNOSTICS _row_count := ROW_COUNT;
        if _row_count > 1 then
            perform reclada.raise_exception('Can not match component objects',_f_name);
        elsif _row_count = 1 then
            return ('{"message": "Installing component, create_subclass('
                        || _new_class
                        || '), status = ''delete / create_subclass''"}'
                    )::jsonb;
        end if;

        insert into dev.component_object( data, status  )
                select _data, 'create_subclass';
            return ('{"message": "Installing component, create_subclass('
                        || _new_class
                        || '), status = ''create_subclass''"}'
                    )::jsonb;
    end if;

    _create_obj := jsonb_build_object(
        'class'         , 'jsonschema'   ,
        'GUID'          , _obj_guid::text,
        'transactionID' , _tran_id       ,
        'parentGUID'    , _data->>'parentGUID',
        'attributes'    , jsonb_build_object(
                'forClass'  , _new_class ,
                'schema'    , _schema
            )
        );
        
    select reclada_object.create(_create_obj)
        into _res;
    PERFORM reclada_object.refresh_mv();
    return _res;
END;
$$ LANGUAGE PLPGSQL VOLATILE;

