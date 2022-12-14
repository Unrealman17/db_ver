-- version = 1
-- 2022-09-10 10:10:11.611800--
-- PostgreSQL database dump
--

-- Dumped from database version 13.4 (Debian 13.4-1.pgdg100+1)
-- Dumped by pg_dump version 14.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: dev; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA dev;


--
-- Name: reclada; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada;


--
-- Name: reclada_object; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_object;


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: begin_install_component(text, text, text, text); Type: FUNCTION; Schema: dev; Owner: -
--

CREATE FUNCTION dev.begin_install_component(_name text, _repository text, _commit_hash text, _parent_component_name text DEFAULT ''::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    _guid        uuid;
    _f_name      text = 'dev.begin_install_component';
BEGIN
    perform reclada.raise_exception( '"'|| name ||'" component has is already begun installing.',_f_name)
        from dev.component;

    select guid 
        from reclada.v_component 
            where name = _name
        into _guid;

    _guid = coalesce(_guid,public.uuid_generate_v4());
    _parent_component_name = nullif(_parent_component_name,'');

    insert into dev.component( name,  repository,  commit_hash,  guid,  parent_component_name)
                       select _name, _repository, _commit_hash, _guid, _parent_component_name;

    delete from dev.component_object;
    insert into dev.component_object(data)
        select obj_data
            from reclada.v_component_object
                where component_name = _name;
    return 'OK';
END;
$$;


--
-- Name: downgrade_component(text); Type: FUNCTION; Schema: dev; Owner: -
--

CREATE FUNCTION dev.downgrade_component(_component_name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    CREATE TEMP TABLE del_comp(
        tran_id bigint,
        id bigint,
        guid uuid
    );


    insert into del_comp(tran_id, id, guid)
        SELECT    transaction_id, id, guid  
            from reclada.v_component 
                where name = _component_name;

    DELETE from reclada.object 
        WHERE transaction_id  in (select tran_id from del_comp);

    DELETE from del_comp;

    insert into del_comp(tran_id, id, guid)
        SELECT    transaction_id, id, obj_id  
            from reclada.v_object obj
                WHERE obj.class_name = 'Component'
                    and obj.attrs->>'name' = _component_name
                    ORDER BY ID DESC
                    limit 1;
    
    update reclada.object u
        SET active = true
        FROM del_comp c
            WHERE u.transaction_id = c.tran_id
                and NOT EXISTS (
                        SELECT from reclada.object o
                            WHERE o.active 
                                and o.guid = u.guid
                    );

    drop TABLE del_comp;
    return 'OK';
END
$$;


--
-- Name: downgrade_version(); Type: FUNCTION; Schema: dev; Owner: -
--

CREATE FUNCTION dev.downgrade_version() RETURNS text
    LANGUAGE plpgsql
    AS $$
declare 
    current_ver int; 
    downgrade_script text;
    v_state   TEXT;
    v_msg     TEXT;
    v_detail  TEXT;
    v_hint    TEXT;
    v_context TEXT;
BEGIN

    select max(ver) 
        from dev.VER
    into current_ver;
    
    select v.downgrade_script 
        from dev.VER v
            WHERE current_ver = v.ver
        into downgrade_script;

    if COALESCE(downgrade_script,'') = '' then
        RAISE EXCEPTION 'downgrade_script is empty! from dev.downgrade_version()';
    end if;

    perform dev.downgrade_component('db');
    
    EXECUTE downgrade_script;

    -- mark, that chanches applied
    delete 
        from dev.VER v
            where v.ver = current_ver;

    v_msg = 'OK, curren version: ' || (current_ver-1)::text;
    perform reclada.raise_notice(v_msg);
    return v_msg;
EXCEPTION when OTHERS then 
	get stacked diagnostics
        v_state   = returned_sqlstate,
        v_msg     = message_text,
        v_detail  = pg_exception_detail,
        v_hint    = pg_exception_hint,
        v_context = pg_exception_context;

    v_state := format('Got exception:
state   : %s
message : %s
detail  : %s
hint    : %s
context : %s
SQLSTATE: %s
SQLERRM : %s', 
                v_state, 
                v_msg, 
                v_detail, 
                v_hint, 
                v_context,
                SQLSTATE,
                SQLERRM);
    perform dev.reg_notice(v_state);
    return v_state;
END
$$;


--
-- Name: finish_install_component(); Type: FUNCTION; Schema: dev; Owner: -
--

CREATE FUNCTION dev.finish_install_component() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    _f_name   text := 'dev.finish_install_component';
    _count    text := '';
    _parent_component_name text;
    _comp_obj jsonb;
    _data     jsonb;
	_tran_id  bigint := reclada.get_transaction_id();
BEGIN

    perform reclada.raise_exception('Component does not found.',_f_name)
        where not exists(select 1 from dev.component);
    
    select jsonb_build_object(
                                'GUID'          , guid::text,
                                'class'         , 'Component',
                                'transactionID' , _tran_id,
                                'attributes'    , jsonb_build_object(
                                    'name'        , name,
                                    'repository'  , repository,
                                    'commitHash'  , commit_hash
                                )
                            ),
            parent_component_name
        from dev.component
        into _comp_obj,
             _parent_component_name;

    delete from dev.component;

    select count(*) 
        from dev.component_object
            where status = 'need to check'
        into _count;

    perform reclada.raise_notice('To delete: '|| _count ||' objects');

    update dev.component_object
        set status = 'delete'
            where status = 'need to check';

    update dev.component_object
        set data = data 
                    || jsonb_build_object('transactionID',_tran_id)
                    || jsonb_build_object('parentGUID',(_comp_obj  ->>'GUID')::uuid)
            where status != 'delete';

    perform reclada_object.delete(data)
        from dev.component_object
            where status = 'delete';

    FOR _data IN (SELECT data 
                    from dev.component_object 
                        where status = 'create_subclass'
                        ORDER BY id)
    LOOP
        perform reclada_object.create_subclass(_data);
    END LOOP;

    perform reclada_object.create(c.data) v
        from dev.component_object c
            where c.status = 'create';

    perform reclada_object.update(data)
        from dev.component_object
            where status = 'update';

    if exists
    (
        select 
            from reclada.object o
                where o.guid = (_comp_obj->>'GUID')::uuid
    ) then
        perform reclada_object.update(_comp_obj);
    else
        perform reclada_object.create(_comp_obj);
    end if;

    perform reclada_object.refresh_mv();

    return 'OK';

END;
$$;


--
-- Name: reg_notice(text); Type: FUNCTION; Schema: dev; Owner: -
--

CREATE FUNCTION dev.reg_notice(msg text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into dev.t_dbg(msg)
		select msg;
    perform reclada.raise_notice(msg);
END
$$;


--
-- Name: _validate_json_schema_type(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._validate_json_schema_type(type text, data jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  IF type = 'integer' THEN
    IF jsonb_typeof(data) != 'number' THEN
      RETURN false;
    END IF;
    IF trunc(data::text::numeric) != data::text::numeric THEN
      RETURN false;
    END IF;
  ELSE
    IF type != jsonb_typeof(data) THEN
      RETURN false;
    END IF;
  END IF;
  RETURN true;
END;
$$;


--
-- Name: validate_json_schema(jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_json_schema(schema jsonb, data jsonb, root_schema jsonb DEFAULT NULL::jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
  prop text;
  item jsonb;
  path text[];
  types text[];
  pattern text;
  props text[];
BEGIN
  IF root_schema IS NULL THEN
    root_schema = schema;
  END IF;

  IF schema ? 'type' THEN
    IF jsonb_typeof(schema->'type') = 'array' THEN
      types = ARRAY(SELECT jsonb_array_elements_text(schema->'type'));
    ELSE
      types = ARRAY[schema->>'type'];
    END IF;
    IF (SELECT NOT bool_or(public._validate_json_schema_type(type, data)) FROM unnest(types) type) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'properties' THEN
    FOR prop IN SELECT jsonb_object_keys(schema->'properties') LOOP
      IF data ? prop AND NOT public.validate_json_schema(schema->'properties'->prop, data->prop, root_schema) THEN
        RETURN false;
      END IF;
    END LOOP;
  END IF;

  IF schema ? 'required' AND jsonb_typeof(data) = 'object' THEN
    IF NOT ARRAY(SELECT jsonb_object_keys(data)) @>
           ARRAY(SELECT jsonb_array_elements_text(schema->'required')) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'items' AND jsonb_typeof(data) = 'array' THEN
    IF jsonb_typeof(schema->'items') = 'object' THEN
      FOR item IN SELECT jsonb_array_elements(data) LOOP
        IF NOT public.validate_json_schema(schema->'items', item, root_schema) THEN
          RETURN false;
        END IF;
      END LOOP;
    ELSE
      IF NOT (
        SELECT bool_and(i > jsonb_array_length(schema->'items') OR public.validate_json_schema(schema->'items'->(i::int - 1), elem, root_schema))
        FROM jsonb_array_elements(data) WITH ORDINALITY AS t(elem, i)
      ) THEN
        RETURN false;
      END IF;
    END IF;
  END IF;

  IF jsonb_typeof(schema->'additionalItems') = 'boolean' and NOT (schema->'additionalItems')::text::boolean AND jsonb_typeof(schema->'items') = 'array' THEN
    IF jsonb_array_length(data) > jsonb_array_length(schema->'items') THEN
      RETURN false;
    END IF;
  END IF;

  IF jsonb_typeof(schema->'additionalItems') = 'object' THEN
    IF NOT (
        SELECT bool_and(public.validate_json_schema(schema->'additionalItems', elem, root_schema))
        FROM jsonb_array_elements(data) WITH ORDINALITY AS t(elem, i)
        WHERE i > jsonb_array_length(schema->'items')
      ) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'minimum' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric < (schema->>'minimum')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'maximum' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric > (schema->>'maximum')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF COALESCE((schema->'exclusiveMinimum')::text::bool, FALSE) THEN
    IF data::text::numeric = (schema->>'minimum')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF COALESCE((schema->'exclusiveMaximum')::text::bool, FALSE) THEN
    IF data::text::numeric = (schema->>'maximum')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'anyOf' THEN
    IF NOT (SELECT bool_or(public.validate_json_schema(sub_schema, data, root_schema)) FROM jsonb_array_elements(schema->'anyOf') sub_schema) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'allOf' THEN
    IF NOT (SELECT bool_and(public.validate_json_schema(sub_schema, data, root_schema)) FROM jsonb_array_elements(schema->'allOf') sub_schema) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'oneOf' THEN
    IF 1 != (SELECT COUNT(*) FROM jsonb_array_elements(schema->'oneOf') sub_schema WHERE public.validate_json_schema(sub_schema, data, root_schema)) THEN
      RETURN false;
    END IF;
  END IF;

  IF COALESCE((schema->'uniqueItems')::text::boolean, false) THEN
    IF (SELECT COUNT(*) FROM jsonb_array_elements(data)) != (SELECT count(DISTINCT val) FROM jsonb_array_elements(data) val) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'additionalProperties' AND jsonb_typeof(data) = 'object' THEN
    props := ARRAY(
      SELECT key
      FROM jsonb_object_keys(data) key
      WHERE key NOT IN (SELECT jsonb_object_keys(schema->'properties'))
        AND NOT EXISTS (SELECT * FROM jsonb_object_keys(schema->'patternProperties') pat WHERE key ~ pat)
    );
    IF jsonb_typeof(schema->'additionalProperties') = 'boolean' THEN
      IF NOT (schema->'additionalProperties')::text::boolean AND jsonb_typeof(data) = 'object' AND NOT props <@ ARRAY(SELECT jsonb_object_keys(schema->'properties')) THEN
        RETURN false;
      END IF;
    ELSEIF NOT (
      SELECT bool_and(public.validate_json_schema(schema->'additionalProperties', data->key, root_schema))
      FROM unnest(props) key
    ) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? '$ref' THEN
    path := ARRAY(
      SELECT regexp_replace(regexp_replace(path_part, '~1', '/'), '~0', '~')
      FROM UNNEST(regexp_split_to_array(schema->>'$ref', '/')) path_part
    );
    -- ASSERT path[1] = '#', 'only refs anchored at the root are supported';
    IF NOT public.validate_json_schema(root_schema #> path[2:array_length(path, 1)], data, root_schema) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'enum' THEN
    IF NOT EXISTS (SELECT * FROM jsonb_array_elements(schema->'enum') val WHERE val = data) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'minLength' AND jsonb_typeof(data) = 'string' THEN
    IF char_length(data #>> '{}') < (schema->>'minLength')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'maxLength' AND jsonb_typeof(data) = 'string' THEN
    IF char_length(data #>> '{}') > (schema->>'maxLength')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'not' THEN
    IF public.validate_json_schema(schema->'not', data, root_schema) THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'maxProperties' AND jsonb_typeof(data) = 'object' THEN
    IF (SELECT count(*) FROM jsonb_object_keys(data)) > (schema->>'maxProperties')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'minProperties' AND jsonb_typeof(data) = 'object' THEN
    IF (SELECT count(*) FROM jsonb_object_keys(data)) < (schema->>'minProperties')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'maxItems' AND jsonb_typeof(data) = 'array' THEN
    IF (SELECT count(*) FROM jsonb_array_elements(data)) > (schema->>'maxItems')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'minItems' AND jsonb_typeof(data) = 'array' THEN
    IF (SELECT count(*) FROM jsonb_array_elements(data)) < (schema->>'minItems')::numeric THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'dependencies' THEN
    FOR prop IN SELECT jsonb_object_keys(schema->'dependencies') LOOP
      IF data ? prop THEN
        IF jsonb_typeof(schema->'dependencies'->prop) = 'array' THEN
          IF NOT (SELECT bool_and(data ? dep) FROM jsonb_array_elements_text(schema->'dependencies'->prop) dep) THEN
            RETURN false;
          END IF;
        ELSE
          IF NOT public.validate_json_schema(schema->'dependencies'->prop, data, root_schema) THEN
            RETURN false;
          END IF;
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF schema ? 'pattern' AND jsonb_typeof(data) = 'string' THEN
    IF (data #>> '{}') !~ (schema->>'pattern') THEN
      RETURN false;
    END IF;
  END IF;

  IF schema ? 'patternProperties' AND jsonb_typeof(data) = 'object' THEN
    FOR prop IN SELECT jsonb_object_keys(data) LOOP
      FOR pattern IN SELECT jsonb_object_keys(schema->'patternProperties') LOOP
        RAISE NOTICE 'prop %s, pattern %, schema %', prop, pattern, schema->'patternProperties'->pattern;
        IF prop ~ pattern AND NOT public.validate_json_schema(schema->'patternProperties'->pattern, data->prop, root_schema) THEN
          RETURN false;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF schema ? 'multipleOf' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric % (schema->>'multipleOf')::numeric != 0 THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$_$;


--
-- Name: get_transaction_id(); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_transaction_id() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
BEGIN
    return nextval('reclada.transaction_id');
END
$$;


--
-- Name: jsonb_deep_set(jsonb, text[], jsonb); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.jsonb_deep_set(curjson jsonb, globalpath text[], newval jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF curjson is null THEN
        curjson := '{}'::jsonb;
    END IF;
    FOR index IN 1..ARRAY_LENGTH(globalpath, 1) LOOP
        IF curjson #> globalpath[1:index] is null THEN
            curjson := jsonb_set(curjson, globalpath[1:index], '{}');
        END IF;
    END LOOP;
    curjson := jsonb_set(curjson, globalpath, newval);
    RETURN curjson;
END;
$$;


--
-- Name: jsonb_merge(jsonb, jsonb); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.jsonb_merge(current_data jsonb, new_data jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE jsonb_typeof(current_data)
        WHEN 'object' THEN
            CASE jsonb_typeof(new_data)
                WHEN 'object' THEN (
                    SELECT jsonb_object_agg(k,
                        CASE
                            WHEN e2.v IS NULL THEN e1.v
                            WHEN e1.v IS NULL THEN e2.v
                            WHEN e1.v = e2.v THEN e1.v
                            ELSE reclada.jsonb_merge(e1.v, e2.v)
                        END)
                    FROM jsonb_each(current_data) e1(k, v)
                        FULL JOIN jsonb_each(new_data) e2(k, v) USING (k)
                )
                ELSE current_data
            END
        WHEN 'array' THEN current_data || new_data
        ELSE current_data
    END
$$;


--
-- Name: raise_exception(text, text); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.raise_exception(msg text, func_name text DEFAULT '<unknown>'::text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 
    RAISE EXCEPTION '% 
    from: %', msg, func_name;
END
$$;


--
-- Name: raise_notice(text); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.raise_notice(msg text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 
    RAISE NOTICE '%', msg;
END
$$;


--
-- Name: try_cast_uuid(text, integer); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.try_cast_uuid(p_in text, p_default integer DEFAULT NULL::integer) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    return p_in::uuid;
    exception when others then
        return p_default;
end;
$$;


--
-- Name: validate_json(jsonb, text); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.validate_json(_data jsonb, _function text) RETURNS void
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    _schema jsonb;
BEGIN

    -- select reclada.raise_exception('JSON invalid: ' || _data >> '{}')
    select schema 
        from reclada.v_DTO_json_schema
            where _function = function
        into _schema;
    
     IF (_schema is null ) then
        RAISE EXCEPTION 'DTOJsonSchema for function: % not found',
                        _function;
    END IF;

    IF (NOT(public.validate_json_schema(_schema, _data))) THEN
        RAISE EXCEPTION 'JSON invalid: %, schema: %, function: %', 
                        _data #>> '{}'   , 
                        _schema #>> '{}' ,
                        _function;
    END IF;
      

END;
$$;


--
-- Name: validate_json_schema(jsonb); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.validate_json_schema(_data jsonb) RETURNS TABLE(valid_schema jsonb, attributes jsonb, class_name text, class_guid uuid)
    LANGUAGE plpgsql STABLE
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

    SELECT data
        FROM reclada.v_class v
            WHERE v.for_class = _class
                OR v.obj_id::text = _class
            LIMIT 1 
        INTO _schema_obj;

    IF (_schema_obj IS NULL) THEN
        perform reclada.raise_exception('No json schema available for ' || _class_name);
    END IF;

    _class_guid := (_schema_obj->>'GUID')::uuid;

    SELECT  _schema_obj #>> '{attributes,forClass}', 
            _schema_obj #>  '{attributes,schema}'
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
        SELECT  _valid_schema, 
                _attrs       , 
                _class_name  , 
                _class_guid  ;
END;
$$;


--
-- Name: create(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object."create"(data_jsonb jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    branch        uuid;
    _data         jsonb;
    new_data      jsonb;
    _class_name    text;
    _class_uuid   uuid;
    tran_id       bigint;
    _attrs        jsonb;
    schema        jsonb;
    _obj_guid     uuid;
    res           jsonb = '{}'::jsonb;
    affected      uuid[];
    inserted      uuid[];
    _parent_guid  uuid;
    skip_insert     boolean;
    notify_res      jsonb;
    _cnt             int;
    _new_parent_guid uuid;
    _guid_list      text;
    _component_guid uuid;
    _row_count      int;
    _f_name         text = 'reclada_object.create';
BEGIN

    IF (jsonb_typeof(data_jsonb) != 'array') THEN
        data_jsonb := '[]'::jsonb || data_jsonb;
    END IF;

    SELECT guid 
        FROM dev.component 
        INTO _component_guid;

    /*TODO: check if some objects have revision AND others do not */
    branch:= data_jsonb->0->'branch';

    FOR _data IN SELECT jsonb_array_elements(data_jsonb) 
    LOOP

        if _component_guid is not null then
            _attrs      := _data-> 'attributes';
            _obj_guid   := _data->>'GUID'      ;
            select obj_id, for_class 
                from reclada.v_class 
                    where _data->>'class' in (obj_id::text, for_class)
                    LIMIT 1
                into _class_uuid, _class_name;

            perform reclada.raise_exception('You should use reclada_object.create_subclass for new jsonschema.',_f_name)
                where _class_name = 'jsonschema';

            update dev.component_object
                set status = 'ok'
                    where status = 'need to check'
                        and _obj_guid::text      = data->>'GUID'
                        and _attrs               = data-> 'attributes'
                        and _class_uuid::text    = data->>'class'
                        and coalesce(_data->>'parentGUID','null') = coalesce(data->>'parentGUID','null') 
                        ------
                        and _obj_guid is not null;
                        ------

            GET DIAGNOSTICS _row_count := ROW_COUNT;
            if _row_count > 1 then
                perform reclada.raise_exception('Can not match component objects',_f_name);
            elsif _row_count = 1 then
                res = res || '{"message": "Installing component"}'::jsonb;
                res = res || ('{"ok":'
                                || (COALESCE((res->>'ok')::bigint,0) + 1)::text
                                ||'}')::jsonb;
                continue;
            end if;

            update dev.component_object
                set status = 'update',
                    data   = _data
                    where status = 'need to check' 
                        and _obj_guid::text = data->>'GUID'
                        ------
                        and _obj_guid is not null;
                        ------

            GET DIAGNOSTICS _row_count := ROW_COUNT;
            if _row_count > 1 then
                perform reclada.raise_exception('Can not match component objects',_f_name);
            elsif _row_count = 1 then
                res = res || '{"message": "Installing component"}'::jsonb;
                res = res || ('{"update":'
                                || (COALESCE((res->>'update')::bigint,0) + 1)::text
                                ||'}')::jsonb;
                continue;
            end if;
            
            with t as
            (
                select min(id) as id
                    from dev.component_object
                        where status = 'need to check'
                            and _attrs               = data-> 'attributes'
                            and _class_uuid::text    = data->>'class'
                            and coalesce(_data->>'parentGUID','null') = coalesce(data->>'parentGUID','null')
                            ------
                            and _obj_guid is null
                            ------
            )
                update dev.component_object u
                    set status = 'ok'
                        from t
                            where u.id = t.id;
                    
            GET DIAGNOSTICS _row_count := ROW_COUNT;
            if _row_count > 1 then
                perform reclada.raise_exception('Can not match component objects',_f_name);
            elsif _row_count = 1 then
                res = res || '{"message": "Installing component"}'::jsonb;
                res = res || ('{"ok":'
                                || (COALESCE((res->>'ok')::bigint,0) + 1)::text
                                ||'}')::jsonb;
                continue;
            end if;
            
            insert into dev.component_object( data, status  )
                select _data, 'create';
                res = res || '{"message": "Installing component"}'::jsonb;
                res = res || ('{"create":'
                                || (COALESCE((res->>'create')::bigint,0) + 1)::text
                                ||'}')::jsonb;
            continue;
            
        end if;

        SELECT  valid_schema, 
                attributes,
                class_name,
                class_guid 
            FROM reclada.validate_json_schema(_data)
            INTO    schema      , 
                    _attrs      ,
                    _class_name ,
                    _class_uuid ;

        _parent_guid = reclada.try_cast_uuid(_data->>'parentGUID');
        
        skip_insert := false;

        tran_id := (_data->>'transactionID')::bigint;
        IF tran_id IS NULL THEN
            tran_id := reclada.get_transaction_id();
        END IF;

        IF _data->>'id' IS NOT NULL THEN
            RAISE EXCEPTION '%','Field "id" not allow!!!';
        END IF;

        _obj_guid := _data->>'GUID';

        IF (NOT skip_insert) THEN           
            _obj_guid := _data->>'GUID';
            IF EXISTS (
                SELECT FROM reclada.object 
                    WHERE guid = _obj_guid
            ) THEN
                perform reclada.raise_exception ('GUID: '||_obj_guid::text||' is duplicate',_f_name);
            END IF;

            _obj_guid := coalesce(_obj_guid, public.uuid_generate_v4());

            INSERT INTO reclada.object(GUID,class,attributes,transaction_id, parent_guid)
                SELECT  _obj_guid AS GUID,
                        _class_uuid, 
                        _attrs,
                        tran_id,
                        _parent_guid;

            affected := array_append( affected, _obj_guid);
            inserted := array_append( inserted, _obj_guid);

            PERFORM reclada_object.refresh_mv();
        END IF;
    END LOOP;
    

    if _component_guid is null then
        res := array_to_json
                (
                    array
                    (
                        SELECT reclada.jsonb_merge(o.data, o.default_value) AS data
                        FROM reclada.v_active_object o
                        WHERE o.obj_id = ANY (affected)
                    )
                )::jsonb;
    end if;
    
    notify_res := array_to_json
            (
                array
                (
                    SELECT o.data 
                    FROM reclada.v_active_object o
                    WHERE o.obj_id = ANY (inserted)
                )
            )::jsonb; 
    

    RETURN res;
END;
$$;


--
-- Name: create_subclass(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.create_subclass(_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: delete(jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.delete(data jsonb, user_info jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_obj_id              uuid;
    tran_id               bigint;
    _class_name           text;
    _class_name_from_uuid text;
    _uniFields_index_name text;
    _class_uuid           uuid;
    list_id               bigint[];
    _list_class_name      text[];
    _for_class            text;
    _exec_text            text;
    _attrs                jsonb;
    _list_id_json         jsonb;
    _id_from_list         bigint;
    _trigger_guid         uuid;
    _function_guid        uuid;
    _function_name        text;
    _query                text;
    _class_name_from_list_id text;
    _guid_for_check       uuid;
    _text_for_trigger_error text;
BEGIN

    v_obj_id := data->>'GUID';
    tran_id := (data->>'transactionID')::bigint;
    _class_name := data->>'class';

    IF (v_obj_id IS NULL AND _class_name IS NULL AND tran_id IS NULl) THEN
        RAISE EXCEPTION 'Could not delete object with no GUID, class and transactionID';
    END IF;

    _class_uuid := reclada.try_cast_uuid(_class_name);
    IF _class_uuid IS NOT NULL THEN
        SELECT v.for_class 
        FROM reclada.v_class_lite v
        WHERE _class_uuid = v.obj_id
            INTO _class_name_from_uuid;
    END IF;

    WITH t AS
    (    
        UPDATE reclada.object u
            SET active = false
            FROM reclada.object o
                LEFT JOIN
                (   SELECT obj_id FROM reclada_object.get_guid_for_class(_class_name)
                    UNION SELECT _class_uuid WHERE _class_uuid IS NOT NULL
                ) c ON o.class = c.obj_id
                WHERE u.id = o.id AND
                (
                    (v_obj_id = o.GUID AND c.obj_id = o.class AND tran_id = o.transaction_id)

                    OR (v_obj_id = o.GUID AND c.obj_id = o.class AND tran_id IS NULL)
                    OR (v_obj_id = o.GUID AND c.obj_id IS NULL AND tran_id = o.transaction_id)
                    OR (v_obj_id IS NULL AND c.obj_id = o.class AND tran_id = o.transaction_id)

                    OR (v_obj_id = o.GUID AND c.obj_id IS NULL AND tran_id IS NULL)
                    OR (v_obj_id IS NULL AND c.obj_id = o.class AND tran_id IS NULL)
                    OR (v_obj_id IS NULL AND c.obj_id IS NULL AND tran_id = o.transaction_id)
                )
                    AND o.active
                    RETURNING o.id
    ) 
        SELECT
            array
            (
                SELECT t.id FROM t
            )
        INTO list_id;
    SELECT vc.obj_id
    FROM reclada.v_class vc
        WHERE vc.for_class = 'DBTrigger'
    INTO _trigger_guid;
    FOR _id_from_list IN 
        select unnest(list_id)
    LOOP
        SELECT vao.class_name
            FROM reclada.v_object vao
                WHERE vao.id = _id_from_list
            INTO _class_name_from_list_id;
        IF _class_name_from_list_id = 'DBTriggerFunction' THEN
            SELECT vva.obj_id
                FROM reclada.v_object vva
                    WHERE vva.id = _id_from_list
                INTO _guid_for_check;
            SELECT string_agg(tn.trigger_name, ', ')
                FROM (
                    SELECT (vaa.attrs ->> 'name') as trigger_name
                        FROM reclada.v_active_object vaa
                            WHERE vaa.class_name = 'DBTrigger'
                            AND (vaa.attrs ->> 'function')::uuid = _guid_for_check
                ) tn
                INTO _text_for_trigger_error;
            IF _text_for_trigger_error IS NOT NULL THEN
                RAISE EXCEPTION 'Could not delete DBTriggerFunction with existing reference to DBTrigger: (%)',_text_for_trigger_error;  
            END IF;
        END IF; 
    END LOOP;


    SELECT array_to_json
    (
        array
        (
            SELECT reclada.jsonb_merge(o.data, o.default_value) AS data
            FROM reclada.v_object o
            WHERE o.id IN (SELECT unnest(list_id))
        )
    )::jsonb
    INTO data;


    SELECT string_agg(t.q,' ')
        FROM (
            SELECT 'DROP '
                        || CASE o.class_name WHEN 'DBTriggerFunction' THEN 'Function' ELSE o.class_name END 
                        ||' reclada.'
                        ||(attrs->>'name')
                        ||';' AS q
                FROM reclada.v_object o
                WHERE o.id IN (SELECT unnest(list_id))
                    AND o.class_name in ('Index','View','Function', 'DBTriggerFunction')
        ) t
        into _exec_text;    
    if _exec_text is not null then
        EXECUTE _exec_text;
    end if;


    IF (jsonb_array_length(data) <= 1) THEN
        data := data->0;
    END IF;
    
    IF (data IS NULL) THEN
        RAISE EXCEPTION 'Could not delete object, no such GUID';
    END IF;

    SELECT array_agg(distinct class_name)
    FROM reclada.v_object vo
    WHERE class_name IN ('jsonschema','User')
        AND id = ANY(list_id)
        INTO _list_class_name;
    
    PERFORM reclada_object.refresh_mv();

    RETURN data;
END;
$$;


--
-- Name: get_guid_for_class(text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_guid_for_class(class text) RETURNS TABLE(obj_id uuid)
    LANGUAGE sql STABLE
    AS $$
    SELECT obj_id
        FROM reclada.v_class_lite
            WHERE for_class = class
$$;


--
-- Name: get_jsonschema_guid(); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_jsonschema_guid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
    SELECT class
        FROM reclada.object o
            where o.GUID = 
                (
                    select class 
                        from reclada.object 
                            where class is not null 
                    limit 1
                )
$$;


--
-- Name: refresh_mv(); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.refresh_mv() RETURNS void
    LANGUAGE plpgsql
    AS $$

BEGIN

    REFRESH MATERIALIZED VIEW reclada.v_class_lite;

END;
$$;


--
-- Name: update(jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.update(_data jsonb, user_info jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _f_name       TEXT = 'reclada_object.update';
    _class_name   text;
    _class_uuid   uuid;
    _obj_id       uuid;
    _attrs        jsonb;
    schema        jsonb;
    old_obj       jsonb;
    branch        uuid;
    _parent_guid  uuid;
    _obj_guid     uuid;
    _cnt          int;
    _tran_id      bigint;
    _guid_list    text;
BEGIN

    SELECT  valid_schema, 
            attributes,
            class_name,
            class_guid 
        FROM reclada.validate_json_schema(_data)
        INTO    schema      , 
                _attrs      ,
                _class_name ,
                _class_uuid ;

    _obj_id := _data->>'GUID';
    IF (_obj_id IS NULL) THEN
        perform reclada.raise_exception('Could not update object with no GUID',_f_name);
    END IF;

    _tran_id = coalesce(    
                    (_data->>'transactionID')::bigint, 
                    (
                        select transaction_id 
                            from reclada.v_active_object 
                                where obj_id = _obj_id
                    )
                );

    -- don't allow update jsonschema
    if _class_name = 'jsonschema' then
        perform reclada.raise_exception('Can''t update jsonschema',_f_name);
    end if;

    SELECT 	v.data
        FROM reclada.v_object v
	        WHERE v.obj_id = _obj_id
                AND v.class_name = _class_name 
	    INTO old_obj;

    IF (old_obj IS NULL) THEN
        perform reclada.raise_exception('Could not update object, no such id');
    END IF;

    _parent_guid = reclada.try_cast_uuid(_data->>'parentGUID');
    
    IF (_parent_guid IS NULL) THEN
        _parent_guid := old_obj->>'parentGUID';
    END IF;
    
    with t as 
    (
        update reclada.object o
            set active = false
                where o.GUID = _obj_id
                    and active 
                        RETURNING id
    )
    INSERT INTO reclada.object( GUID,
                                class,
                                active,
                                attributes,
                                transaction_id,
                                parent_guid
                              )
        select  v.obj_id,
                _class_uuid,
                true,--active 
                _attrs ,
                _tran_id,
                _parent_guid
            FROM reclada.v_object v
            JOIN 
            (   
                select id 
                    FROM 
                    (
                        select id, 1 as q
                            from t
                        union 
                        select id, 2 as q
                            from reclada.object ro
                                where ro.guid = _obj_id
                                    ORDER BY ID DESC 
                                        LIMIT 1
                    ) ta
                    ORDER BY q ASC 
                        LIMIT 1
            ) as tt
                on tt.id = v.id
	            WHERE v.obj_id = _obj_id;

    PERFORM reclada_object.refresh_mv();

    SELECT reclada.jsonb_merge(v.data, v.default_value) AS data
        FROM reclada.v_active_object v
            WHERE v.obj_id = _obj_id
        INTO _data;

    RETURN _data;
END;
$$;


--
-- Name: jsonb_object_agg(jsonb); Type: AGGREGATE; Schema: reclada; Owner: -
--

CREATE AGGREGATE reclada.jsonb_object_agg(jsonb) (
    SFUNC = jsonb_concat,
    STYPE = jsonb,
    INITCOND = '{}'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: component; Type: TABLE; Schema: dev; Owner: -
--

CREATE TABLE dev.component (
    name text NOT NULL,
    repository text NOT NULL,
    commit_hash text NOT NULL,
    guid uuid NOT NULL,
    parent_component_name text
);


--
-- Name: component_object; Type: TABLE; Schema: dev; Owner: -
--

CREATE TABLE dev.component_object (
    id bigint NOT NULL,
    status text DEFAULT 'need to check'::text NOT NULL,
    data jsonb NOT NULL
);


--
-- Name: component_object_id_seq; Type: SEQUENCE; Schema: dev; Owner: -
--

ALTER TABLE dev.component_object ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dev.component_object_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: meta_data; Type: TABLE; Schema: dev; Owner: -
--

CREATE TABLE dev.meta_data (
    id bigint NOT NULL,
    ver bigint,
    data jsonb
);


--
-- Name: meta_data_id_seq; Type: SEQUENCE; Schema: dev; Owner: -
--

ALTER TABLE dev.meta_data ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dev.meta_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: t_dbg; Type: TABLE; Schema: dev; Owner: -
--

CREATE TABLE dev.t_dbg (
    id integer NOT NULL,
    msg text NOT NULL,
    time_when timestamp with time zone DEFAULT now()
);


--
-- Name: t_dbg_id_seq; Type: SEQUENCE; Schema: dev; Owner: -
--

ALTER TABLE dev.t_dbg ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dev.t_dbg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ver; Type: TABLE; Schema: dev; Owner: -
--

CREATE TABLE dev.ver (
    id integer NOT NULL,
    ver integer NOT NULL,
    ver_str text,
    upgrade_script text NOT NULL,
    downgrade_script text NOT NULL,
    run_at timestamp with time zone DEFAULT now()
);


--
-- Name: ver_id_seq; Type: SEQUENCE; Schema: dev; Owner: -
--

ALTER TABLE dev.ver ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dev.ver_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: object; Type: TABLE; Schema: reclada; Owner: -
--

CREATE TABLE reclada.object (
    id bigint NOT NULL,
    attributes jsonb NOT NULL,
    transaction_id bigint NOT NULL,
    created_time timestamp with time zone DEFAULT now(),
    class uuid NOT NULL,
    guid uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    parent_guid uuid,
    active boolean DEFAULT true
);


--
-- Name: object_id_seq; Type: SEQUENCE; Schema: reclada; Owner: -
--

ALTER TABLE reclada.object ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME reclada.object_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 10
);


--
-- Name: transaction_id; Type: SEQUENCE; Schema: reclada; Owner: -
--

CREATE SEQUENCE reclada.transaction_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: v_class_lite; Type: MATERIALIZED VIEW; Schema: reclada; Owner: -
--

CREATE MATERIALIZED VIEW reclada.v_class_lite AS
 WITH RECURSIVE objects_schemas AS (
         SELECT obj_1.id,
            obj_1.guid AS obj_id,
            (obj_1.attributes ->> 'forClass'::text) AS for_class,
            obj_1.created_time,
            obj_1.attributes,
            obj_1.active
           FROM reclada.object obj_1
          WHERE (obj_1.class = reclada_object.get_jsonschema_guid())
        ), paths_to_default AS (
         SELECT ((('{'::text || row_attrs_base.key) || '}'::text))::text[] AS path_head,
            row_attrs_base.value AS path_tail,
            o.obj_id
           FROM (objects_schemas o
             CROSS JOIN LATERAL jsonb_each(o.attributes) row_attrs_base(key, value))
          WHERE ((jsonb_typeof(row_attrs_base.value) = 'object'::text) AND ((o.attributes)::text ~~ '%default%'::text))
        UNION ALL
         SELECT (p.path_head || row_attrs_rec.key) AS path_head,
            row_attrs_rec.value AS path_tail,
            p.obj_id
           FROM (paths_to_default p
             CROSS JOIN LATERAL jsonb_each(p.path_tail) row_attrs_rec(key, value))
          WHERE (jsonb_typeof(row_attrs_rec.value) = 'object'::text)
        ), tmp AS (
         SELECT reclada.jsonb_deep_set('{}'::jsonb, t.path_head[(array_position(t.path_head, 'properties'::text) + 1):], (t.path_tail -> 'default'::text)) AS default_jsonb,
            t.obj_id
           FROM paths_to_default t
          WHERE ((t.path_tail -> 'default'::text) IS NOT NULL)
        ), default_field AS (
         SELECT (format('{"attributes": %s}'::text, reclada.jsonb_object_agg(tmp.default_jsonb)))::jsonb AS default_value,
            tmp.obj_id
           FROM tmp
          GROUP BY tmp.obj_id
        )
 SELECT obj.id,
    obj.obj_id,
    obj.for_class,
    obj.created_time,
    obj.attributes,
    obj.active,
    def.default_value
   FROM (objects_schemas obj
     LEFT JOIN default_field def ON ((def.obj_id = obj.obj_id)))
  WITH NO DATA;


--
-- Name: v_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_object AS
 SELECT t.id,
    t.guid AS obj_id,
    t.class,
    t.created_time,
    t.attributes AS attrs,
    cl.for_class AS class_name,
    cl.default_value,
    (( SELECT (json_agg(tmp.*) -> 0)
           FROM ( SELECT t.guid AS "GUID",
                    t.class,
                    t.active,
                    t.attributes,
                    t.transaction_id AS "transactionID",
                    t.parent_guid AS "parentGUID",
                    t.created_time AS "createdTime") tmp))::jsonb AS data,
    t.active,
    t.transaction_id,
    t.parent_guid
   FROM (reclada.object t
     LEFT JOIN reclada.v_class_lite cl ON ((cl.obj_id = t.class)));


--
-- Name: v_active_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_active_object AS
 SELECT t.id,
    t.obj_id,
    t.class,
    t.active,
    t.created_time,
    t.class_name,
    t.attrs,
    t.data,
    t.transaction_id,
    t.parent_guid,
    t.default_value
   FROM reclada.v_object t
  WHERE t.active;


--
-- Name: v_class; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_class AS
 SELECT obj.id,
    obj.obj_id,
    cl.for_class,
    obj.created_time,
    obj.attrs,
    obj.active,
    obj.data,
    obj.parent_guid,
    cl.default_value
   FROM (reclada.v_class_lite cl
     JOIN reclada.v_active_object obj ON ((cl.id = obj.id)));


--
-- Name: v_component; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_component AS
 SELECT obj.id,
    obj.obj_id AS guid,
    (obj.attrs ->> 'name'::text) AS name,
    (obj.attrs ->> 'repository'::text) AS repository,
    (obj.attrs ->> 'commitHash'::text) AS commit_hash,
    obj.transaction_id,
    obj.created_time,
    obj.attrs,
    obj.active,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'Component'::text);


--
-- Name: v_component_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_component_object AS
 SELECT o.id,
    c.name AS component_name,
    c.guid AS component_guid,
    o.transaction_id,
    o.class_name,
    o.obj_id,
    o.data AS obj_data
   FROM (reclada.v_component c
     JOIN reclada.v_active_object o ON ((o.parent_guid = c.guid)));


--
-- Data for Name: component; Type: TABLE DATA; Schema: dev; Owner: -
--

COPY dev.component (name, repository, commit_hash, guid, parent_component_name) FROM stdin;
\.


--
-- Data for Name: component_object; Type: TABLE DATA; Schema: dev; Owner: -
--

COPY dev.component_object (id, status, data) FROM stdin;
\.


--
-- Data for Name: meta_data; Type: TABLE DATA; Schema: dev; Owner: -
--

COPY dev.meta_data (id, ver, data) FROM stdin;
\.


--
-- Data for Name: t_dbg; Type: TABLE DATA; Schema: dev; Owner: -
--

COPY dev.t_dbg (id, msg, time_when) FROM stdin;
\.


--
-- Data for Name: ver; Type: TABLE DATA; Schema: dev; Owner: -
--

COPY dev.ver (id, ver, ver_str, upgrade_script, downgrade_script, run_at) FROM stdin;
1	1	0	select public.raise_exception ('This is 1 version');	select public.raise_exception ('This is 1 version');	2021-09-22 14:50:17.832813+00
\.


--
-- Data for Name: object; Type: TABLE DATA; Schema: reclada; Owner: -
--

COPY reclada.object (id, attributes, transaction_id, created_time, class, guid, parent_guid, active) FROM stdin;
1	{"schema": {"type": "object", "required": ["forClass", "schema"], "properties": {"schema": {"type": "object"}, "forClass": {"type": "string"}, "parentList": {"type": "array", "items": {"type": "string"}}}}, "version": 1, "forClass": "jsonschema", "parentList": []}	1	2021-09-22 14:50:50.411942+00	5362d59b-82a1-4c7c-8ec3-07c256009fb0	5362d59b-82a1-4c7c-8ec3-07c256009fb0	\N	t
2	{"schema": {"type": "object", "required": [], "properties": {}}, "version": 1, "forClass": "RecladaObject", "parentList": []}	1	2021-09-22 14:50:50.411942+00	5362d59b-82a1-4c7c-8ec3-07c256009fb0	ab9ab26c-8902-43dd-9f1a-743b14a89825	\N	t
3	{"schema": {"type": "object", "$defs": {}, "required": ["name", "commitHash", "repository"], "properties": {"name": {"type": "string"}, "commitHash": {"type": "string"}, "repository": {"type": "string"}}}, "version": 1, "forClass": "Component", "parentList": ["ab9ab26c-8902-43dd-9f1a-743b14a89825"]}	1	2022-09-10 06:27:25.409281+00	5362d59b-82a1-4c7c-8ec3-07c256009fb0	d8585984-317b-4be8-bf50-99e561a17e03	\N	t
4	{"schema": {"type": "object", "required": ["name", "weight", "color"], "properties": {"name": {"type": "string"}, "color": {"type": "string"}, "weight": {"type": "number"}}}, "forClass": "Cat"}	2	2022-09-13 09:46:58.440864+00	5362d59b-82a1-4c7c-8ec3-07c256009fb0	c04a31c7-f8e4-4aaa-b8fe-c92bdc7e4b47	1e59e2ae-ab11-44e9-b54b-a769964c803f	t
5	{"name": "Alex", "color": "white", "weight": 42}	2	2022-09-13 09:46:58.440864+00	c04a31c7-f8e4-4aaa-b8fe-c92bdc7e4b47	9a6a0461-071b-4f89-9f6c-22829b137437	1e59e2ae-ab11-44e9-b54b-a769964c803f	t
6	{"name": "db", "commitHash": "eb3c3687db036a59bb281ff2adc77ca5b9899114", "repository": "https://github.com/Unrealman17/db_ver"}	2	2022-09-13 09:46:58.440864+00	d8585984-317b-4be8-bf50-99e561a17e03	1e59e2ae-ab11-44e9-b54b-a769964c803f	\N	t
\.


--
-- Name: component_object_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.component_object_id_seq', 5, true);


--
-- Name: meta_data_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.meta_data_id_seq', 1, true);


--
-- Name: t_dbg_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.t_dbg_id_seq', 1, true);


--
-- Name: ver_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.ver_id_seq', 1, true);


--
-- Name: object_id_seq; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.object_id_seq', 6, true);


--
-- Name: transaction_id; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.transaction_id', 2, true);


--
-- Name: component_object component_object_pkey; Type: CONSTRAINT; Schema: dev; Owner: -
--

ALTER TABLE ONLY dev.component_object
    ADD CONSTRAINT component_object_pkey PRIMARY KEY (id);


--
-- Name: meta_data meta_data_id_key; Type: CONSTRAINT; Schema: dev; Owner: -
--

ALTER TABLE ONLY dev.meta_data
    ADD CONSTRAINT meta_data_id_key UNIQUE (id);


--
-- Name: object object_pkey; Type: CONSTRAINT; Schema: reclada; Owner: -
--

ALTER TABLE ONLY reclada.object
    ADD CONSTRAINT object_pkey PRIMARY KEY (id);


--
-- Name: class_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX class_index ON reclada.object USING btree (class);


--
-- Name: guid_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX guid_index ON reclada.object USING hash (guid);


--
-- Name: parent_guid_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX parent_guid_index ON reclada.object USING hash (parent_guid) WHERE (parent_guid IS NOT NULL);


--
-- Name: transaction_id_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX transaction_id_index ON reclada.object USING btree (transaction_id);


--
-- Name: v_class_lite; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_class_lite;


--
-- PostgreSQL database dump complete
--

