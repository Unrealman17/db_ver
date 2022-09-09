-- version = 2
-- 2022-09-09 18:03:54.666489--
-- PostgreSQL database dump
--

-- Dumped from database version 13.4
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
-- Name: aws_commons; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS aws_commons WITH SCHEMA public;


--
-- Name: EXTENSION aws_commons; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION aws_commons IS 'Common data types across AWS services';


--
-- Name: aws_lambda; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS aws_lambda WITH SCHEMA public;


--
-- Name: EXTENSION aws_lambda; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION aws_lambda IS 'AWS Lambda integration';


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
        guid uuid,
        name text,
        rev_num bigint
    );

    with recursive t as (
        SELECT  transaction_id, 
                id, 
                guid, 
                name, 
                null as pre, 
                null::bigint as pre_id,
                0 as lvl,
                c.revision_num
            from reclada.v_component c
                WHERE not exists(
                        SELECT 
                            FROM reclada.v_component_object co 
                                where co.obj_id = c.guid
                    )
        union
        select  cc.transaction_id, 
                cc.id, 
                cc.guid, 
                cc.name, 
                t.name as pre, 
                t.id as pre_id,
                t.lvl+1 as lvl,
                cc.revision_num
            from t
            join reclada.v_component_object co
                on t.guid = co.component_guid
            join reclada.v_component cc
                on cc.id = co.id
    ),
    h as (
        SELECT  t.transaction_id, 
                t.id, 
                t.guid, 
                t.name, 
                t.pre, 
                t.pre_id, 
                t.lvl,
                t.revision_num
            FROM t
                where name = _component_name
        union
        select  t.transaction_id, 
                t.id, 
                t.guid, 
                t.name, 
                t.pre, 
                t.pre_id, 
                t.lvl,
                null revision_num
            FROM h
            JOIN t
                on t.pre_id = h.id
    )
    insert into del_comp(tran_id, id, guid, name, rev_num)
        SELECT    transaction_id, id, guid, name, revision_num  
            FROM h;

    DELETE from reclada.object 
        WHERE transaction_id  in (select tran_id from del_comp);


    with recursive t as (
        SELECT o.transaction_id, o.obj_id
            from reclada.v_object o
                WHERE o.obj_id = (SELECT guid from del_comp where name = _component_name)
                    AND coalesce(revision_num, 1) = coalesce(
                            (SELECT rev_num from del_comp where name = _component_name), 
                            1
                        ) - 1
        union 
        select o.transaction_id, o.obj_id
            from t
            JOIN reclada.v_relationship r
                ON r.parent_guid = t.obj_id
                    AND 'data of reclada-component' = r.type
            join reclada.v_object o
                on o.obj_id = r.subject
                    and o.transaction_id >= t.transaction_id
                    and o.class_name = 'Component'
    )
    update reclada.object u
        SET status = reclada_object.get_active_status_obj_id()
        FROM t c
            WHERE u.transaction_id = c.transaction_id
                and NOT EXISTS (
                        SELECT from reclada.object o
                            WHERE o.status != reclada_object.get_archive_status_obj_id()
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
        set data = data || jsonb_build_object('transactionID',_tran_id)
            where status != 'delete';

    perform reclada_object.delete(data)
        from dev.component_object
            where status = 'delete';

    FOR _data IN (SELECT data 
                    from dev.component_object 
                        where status = 'create_subclass'
                        ORDER BY id)
    LOOP
        perform reclada_object.create_relationship(
                'data of reclada-component',
                (_comp_obj ->>'GUID')::uuid ,
                (cr.v ->>'GUID')::uuid ,
                '{}'::jsonb            ,
                (_comp_obj  ->>'GUID')::uuid,
                _tran_id
            )
            from (select reclada_object.create_subclass(_data)#>'{0}' v) cr;
    END LOOP;

    perform reclada_object.create_relationship(
                'data of reclada-component',
                (_comp_obj     ->>'GUID')::uuid ,
                (el.value ->>'GUID')::uuid ,
                '{}'::jsonb                ,
                (_comp_obj     ->>'GUID')::uuid,
                _tran_id
            )
        from dev.component_object c
        cross join lateral (
            select reclada_object.create(c.data) v
        ) cr
        cross join lateral jsonb_array_elements(cr.v) el
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

    perform reclada_object.create_relationship(
                'data of reclada-component',
                c.guid ,
                (_comp_obj     ->>'GUID')::uuid ,
                '{}'::jsonb                ,
                c.guid ,
                _tran_id
            )
        from reclada.v_component c
            where _parent_component_name = c.name;

    perform reclada_object.refresh_mv('All');

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
-- Name: create_revision(character varying, uuid, uuid, bigint); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.create_revision(userid character varying, branch uuid, obj uuid, tran_id bigint DEFAULT reclada.get_transaction_id()) RETURNS uuid
    LANGUAGE sql
    AS $$
    INSERT INTO reclada.object
        (
            class,
            attributes,
            transaction_id
        )
               
        VALUES
        (
            (reclada_object.get_schema('revision')->>'GUID')::uuid,-- class,
            format                    -- attributes
            (                         
                '{
                    "num": %s,
                    "user": "%s",
                    "dateTime": "%s",
                    "branch": "%s"
                }',
                (
                    select count(*) + 1
                        from reclada.object o
                            where o.GUID = obj
                ),
                userid,
                now(),
                branch
            )::jsonb,
            tran_id
        ) RETURNING (GUID)::uuid;
    --nextval('reclada.reclada_revisions'),
$$;


--
-- Name: get_validation_schema(uuid); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_validation_schema(class_guid uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    _schema_obj     jsonb;
    _properties     jsonb = '{}'::jsonb;
    _required       jsonb = '[]'::jsonb;
    _parent_schema  jsonb ;
    _parent_list    jsonb ;
    _parent         uuid ;
    _res            jsonb = '{}'::jsonb;
    _f_name         text = 'reclada.get_validation_schema';
BEGIN

    SELECT reclada_object.get_schema(class_guid::text) 
        INTO _schema_obj;

    IF (_schema_obj IS NULL) THEN
        perform reclada.raise_exception('No json schema available for ' || class_guid, _f_name);
    END IF;

    _parent_list = _schema_obj#>'{attributes,parentList}';

    FOR _parent IN SELECT jsonb_array_elements_text(_parent_list ) 
    LOOP
        _parent_schema := reclada.get_validation_schema(_parent);
        _properties := _properties || coalesce((_parent_schema->'properties'),'{}'::jsonb);
        _required   := _required   || coalesce((_parent_schema->'required'  ),'[]'::jsonb);
        _res := _res || _parent_schema ;  
    END LOOP;
    
    _parent_schema := _schema_obj#>'{attributes,schema}';
    _properties := _properties || coalesce((_parent_schema->'properties'),'{}'::jsonb);
    _required   := _required   || coalesce((_parent_schema->'required'  ),'[]'::jsonb);
    _res := _res || _parent_schema ;  
    _res := _res || jsonb_build_object( 'required'  , _required,
                                        'properties', _properties);
    return _res;
END;
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

    SELECT reclada_object.get_schema(_class) 
        INTO _schema_obj;

    IF (_schema_obj IS NULL) THEN
        perform reclada.raise_exception('No json schema available for ' || _class_name);
    END IF;

    _class_guid := (_schema_obj->>'GUID')::uuid;

    SELECT  _schema_obj #>> '{attributes,forClass}', 
            reclada.get_validation_schema(_class_guid)
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
-- Name: cast_jsonb_to_postgres(text, text, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.cast_jsonb_to_postgres(key_path text, type text, type_of_array text DEFAULT 'text'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
        CASE
            WHEN type = 'string' THEN
                format(E'(%s#>>\'{}\')::text', key_path)
            WHEN type = 'number' THEN
                format(E'(%s)::numeric', key_path)
            WHEN type = 'boolean' THEN
                format(E'(%s)::boolean', key_path)
            WHEN type = 'array' THEN
                format(
                    E'ARRAY(SELECT jsonb_array_elements_text(%s)::%s)',
                    key_path,
                     CASE
                        WHEN type_of_array = 'string' THEN 'text'
                        WHEN type_of_array = 'number' THEN 'numeric'
                        WHEN type_of_array = 'boolean' THEN 'boolean'
                     END
                    )
        END
$$;


--
-- Name: create(jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object."create"(data_jsonb jsonb, user_info jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
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
                    ORDER BY version DESC 
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

            PERFORM reclada_object.refresh_mv(_class_name);
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
-- Name: create_relationship(text, uuid, uuid, jsonb, uuid, bigint); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.create_relationship(_rel_type text, _obj_guid uuid, _subj_guid uuid, _extra_attrs jsonb DEFAULT '{}'::jsonb, _parent_guid uuid DEFAULT NULL::uuid, _tran_id bigint DEFAULT reclada.get_transaction_id()) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _rel_cnt    int;
    _obj        jsonb;
BEGIN

    IF _obj_GUID IS NULL OR _subj_GUID IS NULL THEN
        RAISE EXCEPTION 'Object GUID or Subject GUID IS NULL';
    END IF;

    SELECT count(*)
    FROM reclada.v_active_object
    WHERE class_name = 'Relationship'
        AND (attrs->>'object')::uuid   = _obj_GUID
        AND (attrs->>'subject')::uuid  = _subj_GUID
        AND attrs->>'type'                      = _rel_type
            INTO _rel_cnt;
    IF (_rel_cnt = 0) THEN
        _obj := format('{
            "class": "Relationship",
            "transactionID": %s,
            "attributes": {
                    "type": "%s",
                    "object": "%s",
                    "subject": "%s"
                }
            }',
            _tran_id :: text,
            _rel_type,
            _obj_GUID,
            _subj_GUID)::jsonb;
        _obj := jsonb_set (_obj, '{attributes}', _obj->'attributes' || _extra_attrs);   
        if _parent_guid is not null then
            _obj := jsonb_set (_obj, '{parentGUID}', to_jsonb(_parent_guid) );   
        end if;

        RETURN  reclada_object.create( _obj);
    ELSE
        RETURN '{}'::jsonb;
    END IF;
END;
$$;


--
-- Name: create_subclass(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.create_subclass(_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
    _class_list     jsonb;
    _res            jsonb = '{}'::jsonb;
    _class          text;
    _properties     jsonb;
    _p_properties   jsonb;
    _required       jsonb;
    _p_required     jsonb;
    _parent_list    jsonb := '[]';
    _new_class      text;
    attrs           jsonb;
    class_schema    jsonb;
    _version        integer;
    class_guid      uuid;
    _uniFields      jsonb;
    _idx_name       text;
    _f_list         text;
    _field          text;
    _f_name         text = 'reclada_object.create_subclass';
    _partial_clause text;
    _field_name     text;
    _create_obj     jsonb;
    _component_guid uuid;
    _obj_guid       uuid;
    _row_count      int;
    _defs           jsonb = '{}'::jsonb;
	_tran_id        bigint;
BEGIN

    _class_list := _data->'class';
    IF (_class_list IS NULL) THEN
        perform reclada.raise_exception('The reclada object class is not specified',_f_name);
    END IF;

    _obj_guid := COALESCE((_data->>'GUID')::uuid, public.uuid_generate_v4());
    _tran_id  := COALESCE((_data->>'transactionID')::bigint, reclada.get_transaction_id());

    IF (jsonb_typeof(_class_list) != 'array') THEN
        _class_list := '[]'::jsonb || _class_list;
    END IF;

    attrs := _data->'attributes';
    IF (attrs IS NULL) THEN
        PERFORM reclada.raise_exception('The reclada object must have attributes',_f_name);
    END IF;

    _new_class  := attrs->>'newClass';
    _properties := COALESCE(attrs -> 'properties','{}'::jsonb);
    _required   := COALESCE(attrs -> 'required'  ,'[]'::jsonb);
    _defs       := COALESCE(attrs -> '$defs'     ,'{}'::jsonb);
    SELECT guid 
        FROM dev.component 
        INTO _component_guid;

    if _component_guid is not null then
        update dev.component_object
            set status = 'ok'
            where status = 'need to check'
                and _new_class  =          data #>> '{attributes,forClass}'
                and _properties = COALESCE(data #>  '{attributes,schema,properties}','{}'::jsonb)
                and _required   = COALESCE(data #>  '{attributes,schema,required}'  ,'[]'::jsonb)
                and _defs       = COALESCE(data #>  '{attributes,schema,$defs}'     ,'{}'::jsonb)
                and jsonb_array_length(_class_list) = jsonb_array_length(data #> '{attributes,parentList}');

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
            return _res;
        end if;

        insert into dev.component_object( data, status  )
                select _data, 'create_subclass';
            return _res;
    end if;

    FOR _class IN SELECT jsonb_array_elements_text(_class_list)
    LOOP

        SELECT reclada_object.get_schema(_class) 
            INTO class_schema;

        IF (class_schema IS NULL) THEN
            perform reclada.raise_exception('No json schema available for ' || _class, _f_name);
        END IF;
        
        SELECT class_schema->>'GUID'
            INTO class_guid;
        
        _parent_list := _parent_list || to_jsonb(class_guid);

    END LOOP;
   
    SELECT max(version) + 1
    FROM reclada.v_class_lite v
    WHERE v.for_class = _new_class
        INTO _version;

    _version := coalesce(_version,1);

    _create_obj := jsonb_build_object(
        'class'         , 'jsonschema'   ,
        'GUID'          , _obj_guid::text,
        'transactionID' , _tran_id       ,
        'attributes'    , jsonb_build_object(
                'forClass'  , _new_class ,
                'version'   , _version   ,
                'parentList',_parent_list,
                'schema'    , jsonb_build_object(
                    'type'      , 'object'   ,
                    '$defs'     , _defs      ,
                    'properties', _properties,
                    'required'  , _required  
                )
            )
        );
        
    IF ( jsonb_typeof(attrs->'dupChecking') = 'array' ) THEN
        _create_obj := jsonb_set(_create_obj, '{attributes,dupChecking}',attrs->'dupChecking');
        IF ( jsonb_typeof(attrs->'dupBehavior') = 'string' ) THEN
            _create_obj := jsonb_set(_create_obj, '{attributes,dupBehavior}',attrs->'dupBehavior');
        END IF;
        IF ( jsonb_typeof(attrs->'isCascade') = 'boolean' ) THEN
            _create_obj := jsonb_set(_create_obj, '{attributes,isCascade}',attrs->'isCascade');
        END IF;
        IF ( jsonb_typeof(attrs->'copyField') = 'string' ) THEN
            _create_obj := jsonb_set(_create_obj, '{attributes,copyField}',attrs->'copyField');
        END IF;
    END IF;
    IF ( jsonb_typeof(attrs->'parentField') = 'string' ) THEN
        _create_obj := jsonb_set(_create_obj, '{attributes,parentField}',attrs->'parentField');
    END IF;
    select reclada_object.create(_create_obj)
        into _res;
    PERFORM reclada_object.refresh_mv('uniFields');
    return _res;
END;
$_$;


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
            SET status = reclada_object.get_archive_status_obj_id()
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
                    AND o.status != reclada_object.get_archive_status_obj_id()
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
    WHERE class_name IN ('jsonschema','User','ObjectStatus')
        AND id = ANY(list_id)
        INTO _list_class_name;
    
    PERFORM reclada_object.refresh_mv(cn)
        FROM unnest( _list_class_name ) AS cn;

    RETURN data;
END;
$$;


--
-- Name: get_active_status_obj_id(); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_active_status_obj_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
    select obj_id 
        from reclada.v_object_status 
            where caption = 'active'
$$;


--
-- Name: get_archive_status_obj_id(); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_archive_status_obj_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
    select obj_id 
        from reclada.v_object_status 
            where caption = 'archive'
$$;


--
-- Name: get_condition_array(jsonb, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_condition_array(data jsonb, key_path text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT
    CONCAT(
        key_path,
        ' ', COALESCE(data->>'operator', '='), ' ',
        format(E'\'%s\'::jsonb', data->'object'#>>'{}')) || CASE WHEN data->>'operator'='<@' THEN ' AND ' || key_path || ' != ''[]''::jsonb' ELSE '' END
$$;


--
-- Name: get_default_user_obj_id(); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_default_user_obj_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
    select obj_id 
        from reclada.v_user 
            where login = 'dev'
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
-- Name: get_query_condition(jsonb, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_query_condition(data jsonb, key_path text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    key          text;
    operator     text;
    value        text;
    res          text;

BEGIN
    IF (data IS NULL OR data = 'null'::jsonb) THEN
        RAISE EXCEPTION 'There is no condition';
    END IF;

    IF (jsonb_typeof(data) = 'object') THEN

        IF (data->'object' IS NULL OR data->'object' = ('null'::jsonb)) THEN
            RAISE EXCEPTION 'There is no object field';
        END IF;

        IF (jsonb_typeof(data->'object') = 'object') THEN
            operator :=  data->>'operator';
            IF operator = '=' then
                key := reclada_object.cast_jsonb_to_postgres(key_path, 'string' );
                RETURN (key || ' ' || operator || ' ''' || (data->'object')::text || '''');
            ELSE
                RAISE EXCEPTION 'The input_jsonb->''object'' can not contain jsonb object';
            END If;
        END IF;

        IF (jsonb_typeof(data->'operator') != 'string' AND data->'operator' IS NOT NULL) THEN
            RAISE EXCEPTION 'The input_jsonb->''operator'' must contain string';
        END IF;

        IF (jsonb_typeof(data->'object') = 'array') THEN
            res := reclada_object.get_condition_array(data, key_path);
        ELSE
            key := reclada_object.cast_jsonb_to_postgres(key_path, jsonb_typeof(data->'object'));
            operator :=  data->>'operator';
            value := reclada_object.jsonb_to_text(data->'object');
            res := key || ' ' || operator || ' ' || value;
        END IF;
    ELSE
        key := reclada_object.cast_jsonb_to_postgres(key_path, jsonb_typeof(data));
        operator := '=';
        value := reclada_object.jsonb_to_text(data);
        res := key || ' ' || operator || ' ' || value;
    END IF;
    RETURN res;

END;
$$;


--
-- Name: get_schema(text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_schema(_class text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
    SELECT data
    FROM reclada.v_class v
    WHERE v.for_class = _class
        OR v.obj_id::text = _class
    ORDER BY v.version DESC
    LIMIT 1
$$;


--
-- Name: jsonb_to_text(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.jsonb_to_text(data jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT
        CASE
            WHEN jsonb_typeof(data) = 'string' THEN
                format(E'\'%s\'', data#>>'{}')
            WHEN jsonb_typeof(data) = 'array' THEN
                format('ARRAY[%s]',
                    (SELECT string_agg(
                        reclada_object.jsonb_to_text(elem),
                        ', ')
                    FROM jsonb_array_elements(data) elem))
            ELSE
                data#>>'{}'
        END
$$;


--
-- Name: list(jsonb, boolean, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.list(data jsonb, gui boolean DEFAULT false, ver text DEFAULT '1'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
    _object_display     jsonb;
    _order_row          jsonb;
BEGIN

    perform reclada.validate_json(data, _f_name);

    tran_id := (data->>'transactionID')::bigint;
    _class := data->>'class';

    order_by_jsonb := data->'orderBy';
    IF ((order_by_jsonb IS NULL) OR
        (order_by_jsonb = 'null'::jsonb) OR
        (order_by_jsonb = '[]'::jsonb)) THEN
        order_by_jsonb := '[{"field": "id", "order": "ASC"}]'::jsonb;
    END IF;

    SELECT  string_agg(
                    format(
                        E'obj.data#>''{%s}'' %s', 
                        T.value->>'field',
                        COALESCE(T.value->>'order', 'ASC')
                    ),
                    ' , '
            )
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
    
    IF ver = '1' then
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
$$;


--
-- Name: refresh_mv(text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.refresh_mv(class_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$

BEGIN
    CASE class_name
        WHEN 'ObjectStatus' THEN
            REFRESH MATERIALIZED VIEW reclada.v_object_status;
        WHEN 'User' THEN
            REFRESH MATERIALIZED VIEW reclada.v_user;
        WHEN 'jsonschema' THEN
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        WHEN 'uniFields' THEN
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        WHEN 'All' THEN
            REFRESH MATERIALIZED VIEW reclada.v_object_status;
            REFRESH MATERIALIZED VIEW reclada.v_user;
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        ELSE
            NULL;
    END CASE;
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
    revid         uuid;
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

    branch := _data->'branch';
    SELECT reclada.create_revision(user_info->>'sub', branch, _obj_id, _tran_id) 
        INTO revid;

    IF (_parent_guid IS NULL) THEN
        _parent_guid := old_obj->>'parentGUID';
    END IF;
    
    with t as 
    (
        update reclada.object o
            set status = reclada_object.get_archive_status_obj_id()
                where o.GUID = _obj_id
                    and status != reclada_object.get_archive_status_obj_id()
                        RETURNING id
    )
    INSERT INTO reclada.object( GUID,
                                class,
                                status,
                                attributes,
                                transaction_id,
                                parent_guid
                              )
        select  v.obj_id,
                _class_uuid,
                reclada_object.get_active_status_obj_id(),--status 
                _attrs || format('{"revision":"%s"}',revid)::jsonb,
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

    PERFORM reclada_object.refresh_mv(_class_name);

    IF ( _class_name = 'jsonschema' AND jsonb_typeof(_attrs->'dupChecking') = 'array') THEN
        PERFORM reclada_object.refresh_mv('uniFields');
    END IF; 

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
    status uuid DEFAULT reclada_object.get_active_status_obj_id() NOT NULL,
    attributes jsonb NOT NULL,
    transaction_id bigint NOT NULL,
    created_time timestamp with time zone DEFAULT now(),
    created_by uuid DEFAULT reclada_object.get_default_user_obj_id(),
    class uuid NOT NULL,
    guid uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    parent_guid uuid
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
            ((obj_1.attributes ->> 'version'::text))::bigint AS version,
            obj_1.created_time,
            obj_1.attributes,
            obj_1.status
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
    obj.version,
    obj.created_time,
    obj.attributes,
    obj.status,
    def.default_value
   FROM (objects_schemas obj
     LEFT JOIN default_field def ON ((def.obj_id = obj.obj_id)))
  WITH NO DATA;


--
-- Name: v_object_status; Type: MATERIALIZED VIEW; Schema: reclada; Owner: -
--

CREATE MATERIALIZED VIEW reclada.v_object_status AS
 SELECT obj.id,
    obj.guid AS obj_id,
    (obj.attributes ->> 'caption'::text) AS caption,
    obj.created_time,
    obj.attributes AS attrs
   FROM reclada.object obj
  WHERE (obj.class IN ( SELECT reclada_object.get_guid_for_class('ObjectStatus'::text) AS get_guid_for_class))
  WITH NO DATA;


--
-- Name: v_user; Type: MATERIALIZED VIEW; Schema: reclada; Owner: -
--

CREATE MATERIALIZED VIEW reclada.v_user AS
 SELECT obj.id,
    obj.guid AS obj_id,
    (obj.attributes ->> 'login'::text) AS login,
    obj.created_time,
    obj.attributes AS attrs
   FROM reclada.object obj
  WHERE ((obj.class IN ( SELECT reclada_object.get_guid_for_class('User'::text) AS get_guid_for_class)) AND (obj.status = reclada_object.get_active_status_obj_id()))
  WITH NO DATA;


--
-- Name: v_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_object AS
 SELECT t.id,
    t.guid AS obj_id,
    t.class,
    ( SELECT ((r.attributes ->> 'num'::text))::bigint AS num
           FROM reclada.object r
          WHERE ((r.class IN ( SELECT reclada_object.get_guid_for_class('revision'::text) AS get_guid_for_class)) AND (r.guid = (NULLIF((t.attributes ->> 'revision'::text), ''::text))::uuid))
         LIMIT 1) AS revision_num,
    os.caption AS status_caption,
    (NULLIF((t.attributes ->> 'revision'::text), ''::text))::uuid AS revision,
    t.created_time,
    t.attributes AS attrs,
    cl.for_class AS class_name,
    cl.default_value,
    (( SELECT (json_agg(tmp.*) -> 0)
           FROM ( SELECT t.guid AS "GUID",
                    t.class,
                    os.caption AS status,
                    t.attributes,
                    t.transaction_id AS "transactionID",
                    t.parent_guid AS "parentGUID",
                    t.created_by AS "createdBy",
                    t.created_time AS "createdTime") tmp))::jsonb AS data,
    u.login AS login_created_by,
    t.created_by,
    t.status,
    t.transaction_id,
    t.parent_guid
   FROM (((reclada.object t
     LEFT JOIN reclada.v_object_status os ON ((t.status = os.obj_id)))
     LEFT JOIN reclada.v_user u ON ((u.obj_id = t.created_by)))
     LEFT JOIN reclada.v_class_lite cl ON ((cl.obj_id = t.class)));


--
-- Name: v_active_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_active_object AS
 SELECT t.id,
    t.obj_id,
    t.class,
    t.revision_num,
    t.status,
    t.status_caption,
    t.revision,
    t.created_time,
    t.class_name,
    t.attrs,
    t.data,
    t.transaction_id,
    t.parent_guid,
    t.default_value
   FROM reclada.v_object t
  WHERE (t.status = reclada_object.get_active_status_obj_id());


--
-- Name: v_class; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_class AS
 SELECT obj.id,
    obj.obj_id,
    cl.for_class,
    cl.version,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
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
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'Component'::text);


--
-- Name: v_relationship; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_relationship AS
 SELECT obj.id,
    obj.obj_id AS guid,
    (obj.attrs ->> 'type'::text) AS type,
    ((obj.attrs ->> 'object'::text))::uuid AS object,
    ((obj.attrs ->> 'subject'::text))::uuid AS subject,
    obj.parent_guid,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'Relationship'::text);


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
    o.data AS obj_data,
    r.guid AS relationship_guid
   FROM ((reclada.v_component c
     JOIN reclada.v_relationship r ON (((r.parent_guid = c.guid) AND ('data of reclada-component'::text = r.type))))
     JOIN reclada.v_active_object o ON ((o.obj_id = r.subject)));


--
-- Name: v_dto_json_schema; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_dto_json_schema AS
 SELECT obj.id,
    obj.obj_id,
    (obj.attrs ->> 'function'::text) AS function,
    (obj.attrs -> 'schema'::text) AS schema,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data,
    obj.parent_guid
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'DTOJsonSchema'::text);


--
-- Name: v_revision; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_revision AS
 SELECT obj.id,
    obj.obj_id,
    ((obj.attrs ->> 'num'::text))::bigint AS num,
    (obj.attrs ->> 'branch'::text) AS branch,
    (obj.attrs ->> 'user'::text) AS "user",
    (obj.attrs ->> 'dateTime'::text) AS date_time,
    (obj.attrs ->> 'old_num'::text) AS old_num,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'revision'::text);


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
3	2	\N	begin;\nSET CLIENT_ENCODING TO 'utf8';\nCREATE TEMP TABLE var_table\n    (\n        ver int,\n        upgrade_script text,\n        downgrade_script text\n    );\n    \ninsert into var_table(ver)\t\n    select max(ver) + 1\n        from dev.VER;\n        \nselect reclada.raise_exception('Can not apply this version!') \n    where not exists\n    (\n        select ver from var_table where ver = 2 --!!! write current version HERE !!!\n    );\n\nCREATE TEMP TABLE tmp\n(\n    id int GENERATED ALWAYS AS IDENTITY,\n    str text\n);\n--{ logging upgrade script\nCOPY tmp(str) FROM  'up.sql' delimiter E'';\nupdate var_table set upgrade_script = array_to_string(ARRAY((select str from tmp order by id asc)),chr(10),'');\ndelete from tmp;\n--} logging upgrade script\t\n\n--{ create downgrade script\nCOPY tmp(str) FROM  'down.sql' delimiter E'';\nupdate tmp set str = drp.v || scr.v\n    from tmp ttt\n    inner JOIN LATERAL\n    (\n        select substring(ttt.str from 4 for length(ttt.str)-4) as v\n    )  obj_file_name ON TRUE\n    inner JOIN LATERAL\n    (\n        select \tsplit_part(obj_file_name.v,'/',1) typ,\n                split_part(obj_file_name.v,'/',2) nam\n    )  obj ON TRUE\n        inner JOIN LATERAL\n    (\n        select case\n                when obj.typ = 'trigger'\n                    then\n                        (select 'DROP '|| obj.typ || ' IF EXISTS '|| obj.nam ||' ON ' || schm||'.'||tbl ||';' || E'\n'\n                        from (\n                            select n.nspname as schm,\n                                   c.relname as tbl\n                            from pg_trigger t\n                                join pg_class c on c.oid = t.tgrelid\n                                join pg_namespace n on n.oid = c.relnamespace\n                            where t.tgname = obj.nam) o)\n                else 'DROP '||obj.typ|| ' IF EXISTS '|| obj.nam || ' ;' || E'\n'\n                end as v\n    )  drp ON TRUE\n    inner JOIN LATERAL\n    (\n        select case \n                when obj.typ in ('function', 'procedure')\n                    then\n                        case \n                            when EXISTS\n                                (\n                                    SELECT 1 a\n                                        FROM pg_proc p \n                                        join pg_namespace n \n                                            on p.pronamespace = n.oid \n                                            where n.nspname||'.'||p.proname = obj.nam\n                                        LIMIT 1\n                                ) \n                                then (select pg_catalog.pg_get_functiondef(obj.nam::regproc::oid))||';'\n                            else ''\n                        end\n                when obj.typ = 'view'\n                    then\n                        case \n                            when EXISTS\n                                (\n                                    select 1 a \n                                        from pg_views v \n                                            where v.schemaname||'.'||v.viewname = obj.nam\n                                        LIMIT 1\n                                ) \n                                then E'CREATE OR REPLACE VIEW '\n                                        || obj.nam\n                                        || E'\nAS\n'\n                                        || (select pg_get_viewdef(obj.nam, true))\n                            else ''\n                        end\n                when obj.typ = 'trigger'\n                    then\n                        case\n                            when EXISTS\n                                (\n                                    select 1 a\n                                        from pg_trigger v\n                                            where v.tgname = obj.nam\n                                        LIMIT 1\n                                )\n                                then (select pg_catalog.pg_get_triggerdef(oid, true)\n                                        from pg_trigger\n                                        where tgname = obj.nam)||';'\n                            else ''\n                        end\n                else \n                    ttt.str\n            end as v\n    )  scr ON TRUE\n    where ttt.id = tmp.id\n        and tmp.str like '--{%/%}';\n    \nupdate var_table set downgrade_script = array_to_string(ARRAY((select str from tmp order by id asc)),chr(10),'');\t\n--} create downgrade script\ndrop table tmp;\n\n\n--{!!! write upgrare script HERE !!!\n\n--\tyou can use "i 'function/reclada_object.get_schema.sql'"\n--\tto run text script of functions\n \n/*\n  you can use "i 'function/reclada_object.get_schema.sql'"\n  to run text script of functions\n*/\n\n\ni 'function/reclada_object.create.sql'\ni 'function/reclada_object.create_subclass.sql'\ni 'function/reclada_object.delete.sql'\ni 'function/reclada_object.list.sql'\ni 'function/reclada_object.update.sql'\ni 'function/dev.finish_install_component.sql'\ni 'function/reclada_object.refresh_mv.sql'\ni 'function/reclada.create_revision.sql'\n\n\nDROP TRIGGER load_staging ON reclada.staging;\n\ndrop table reclada.staging;\n\ndrop VIEW reclada.v_ui_active_object;\n\ndrop VIEW reclada.v_trigger;\n\nDROP FUNCTION reclada_object.perform_trigger_function;\n\nDROP FUNCTION reclada_object.object_insert;\n\nDROP VIEW reclada.v_db_trigger_function;\n\ndrop VIEW reclada.v_import_info;\n\ndrop VIEW reclada.v_task;\n\nDROP FUNCTION reclada_object.need_flat;\n\ndrop VIEW reclada.v_object_display;\n\nDROP FUNCTION reclada.get_duplicates;\n\nDROP VIEW reclada.v_get_duplicates_query;\n\ndrop VIEW reclada.v_default_display;\n\ndrop SCHEMA api CASCADE;\n\ndrop SCHEMA reclada_storage;\n\ndrop SCHEMA reclada_notification CASCADE;\n\ndrop SCHEMA reclada_user CASCADE;\n\ndrop SCHEMA reclada_revision CASCADE;\n\ndrop FUNCTION reclada.load_staging;\n\nDROP FUNCTION reclada_object.list_add;\n\nDROP FUNCTION reclada_object.list_drop;\n\nDROP FUNCTION reclada_object.list_related;\n\nDROP FUNCTION reclada.get_unifield_index_name;\n\nDROP FUNCTION reclada.get_transaction_id_for_import;\n\nDROP FUNCTION reclada.rollback_import;\n\nDROP FUNCTION reclada.get_children;\n\nDROP FUNCTION reclada_object.get_parent_guid;\n\nDROP VIEW reclada.v_parent_field;\n\nDROP FUNCTION reclada_object.get_query_condition_filter;\n\ndrop VIEW reclada.v_filter_mapping;\n\ndrop VIEW reclada.v_filter_inner_operator;\n\ndrop VIEW reclada.v_filter_between;\n\nDROP VIEW reclada.v_filter_available_operator;\n\ndrop OPERATOR reclada.##(boolean,boolean);\n\ndrop FUNCTION reclada.xor;\n\nDROP FUNCTION reclada_object.update_json_by_guid;\n\nDROP FUNCTION reclada_object.update_json;\n\nDROP FUNCTION reclada_object.remove_parent_guid;\n\nDROP FUNCTION reclada_object.parse_filter;\n\nDROP FUNCTION reclada_object.merge;\n\nDROP FUNCTION reclada_object.is_equal;\n\nDROP FUNCTION reclada.random_string;\n\nDROP FUNCTION reclada_object.get_transaction_id;\n\ndrop TABLE reclada.auth_setting;\n\ndrop TABLE reclada.draft;\n\ndrop MATERIALIZED VIEW reclada.v_object_unifields;\n\ndrop TYPE reclada.dp_bhvr;\n\nDROP FUNCTION reclada.try_cast_int;\n\nDROP FUNCTION reclada_object.create_job;\n\nDROP FUNCTION reclada_object.explode_jsonb;\n\nDROP INDEX reclada.height_index_v47;\n\nDROP INDEX reclada.colspan_index_v47;\n\nDROP INDEX reclada.column_index_v47;\n\nDROP INDEX reclada.environment_index_v47;\n\nDROP INDEX reclada.event_index_v47;\n\nDROP INDEX reclada.left_index_v47;\n\nDROP INDEX reclada.nexttask_index_v47;\n\nDROP INDEX reclada.number_index_v47;\n\nDROP INDEX reclada.object_index_v47;\n\nDROP INDEX reclada.row_index_v47;\n\nDROP INDEX reclada.runner_type_index;\n\nDROP INDEX reclada.subject_index_v47;\n\nDROP INDEX reclada.task_index_v47;\n\nDROP INDEX reclada.tasks_index_v47;\n\nDROP INDEX reclada.top_index_v47;\n\nDROP INDEX reclada.tranid_index_v47;\n\nDROP INDEX reclada.triggers_index_v47;\n\nDROP INDEX reclada.width_index_v47;\n\nDROP INDEX reclada.rowspan_index_v47;\n\n\n\n\n\n\n\n\n SELECT reclada.raise_notice('Begin install component db...');\n                SELECT dev.begin_install_component('db','https://github.com/Unrealman17/db_ver','a8c1fb835fedb6b73164c9741f45c584cbd22033');\n                SELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "revision",\n        "properties": {\n            "branch": {"type": "string"},\n            "user": {"type": "string"},\n            "num": {"type": "number"},\n            "dateTime": {"type": "string"}\n        },\n        "required": ["dateTime"]\n    }\n}'::jsonb);\n\n-- 7\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "Component",\n        "properties": {\n            "name": {"type": "string"},\n            "commitHash": {"type": "string"},\n            "repository": {"type": "string"}\n        },\n        "required": ["name","commitHash","repository"]\n    }\n}'::jsonb);\n\n--{ 9 DTOJsonSchema\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "DTOJsonSchema",\n        "properties": {\n            "schema": {"type": "object"},\n            "function": {"type": "string"}\n        },\n        "required": ["schema","function"]\n    }\n}'::jsonb);\n\n     SELECT reclada_object.create('{\n            "GUID":"db0ad26e-a522-4907-a41a-a82a916fdcf9",\n            "class": "DTOJsonSchema",\n            "attributes": {\n                "function": "reclada_object.list",\n                "schema": {\n                    "type": "object",\n                    "anyOf": [\n                        {\n                            "required": [\n                                "transactionID"\n                            ]\n                        },\n                        {\n                            "required": [\n                                "class"\n                            ]\n                        },\n                        {\n                            "required": [\n                                "filter"\n                            ]\n                        }\n                    ],\n                    "properties": {\n                        "class": {\n                            "type": "string"\n                        },\n                        "limit": {\n                            "anyOf": [\n                                {\n                                    "enum": [\n                                        "ALL"\n                                    ],\n                                    "type": "string"\n                                },\n                                {\n                                    "type": "integer"\n                                }\n                            ]\n                        },\n                        "filter": {\n                            "type": "object"\n                        },\n                        "offset": {\n                            "type": "integer"\n                        },\n                        "orderBy": {\n                            "type": "array",\n                            "items": {\n                                "type": "object",\n                                "required": [\n                                    "field"\n                                ],\n                                "properties": {\n                                    "field": {\n                                        "type": "string"\n                                    },\n                                    "order": {\n                                        "enum": [\n                                            "ASC",\n                                            "DESC"\n                                        ],\n                                        "type": "string"\n                                    }\n                                }\n                            }\n                        },\n                        "transactionID": {\n                            "type": "integer"\n                        }\n                    }\n                }\n            }\n            \n        }'::jsonb);\n--} 9 DTOJsonSchema\n\n--{ 11 User\nSELECT reclada_object.create_subclass('{\n    "GUID":"db0db7c0-9b25-4af0-8013-d2d98460cfff",\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "User",\n        "properties": {\n            "login": {"type": "string"}\n        },\n        "required": ["login"]\n    }\n}'::jsonb);\n\n    select reclada_object.create('{\n            "GUID": "db0789c1-1b4e-4815-b70c-4ef060e90884",\n            "class": "User",\n            "attributes": {\n                "login": "dev"\n            }\n        }'::jsonb);\n--} 11 User\n                SELECT dev.finish_install_component();\n\n--}!!! write upgrare script HERE !!!\n\ninsert into dev.ver(ver,upgrade_script,downgrade_script)\n    select ver, upgrade_script, downgrade_script\n        from var_table;\n\n--{ testing downgrade script\nSAVEPOINT sp;\n    select dev.downgrade_version();\nROLLBACK TO sp;\n--} testing downgrade script\n\nselect reclada.raise_notice('OK, current version: ' \n                            || (select ver from var_table)::text\n                          );\ndrop table var_table;\n\ncommit;	-- you can use "--{function/reclada_object.get_schema}"\n-- to add current version of object to downgrade script	2022-09-09 15:04:29.612698+00
\.


--
-- Data for Name: object; Type: TABLE DATA; Schema: reclada; Owner: -
--

COPY reclada.object (id, status, attributes, transaction_id, created_time, created_by, class, guid, parent_guid) FROM stdin;
22	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"caption": "active"}	9	2021-09-22 14:50:50.411942+00	16d789c1-1b4e-4815-b70c-4ef060e90884	14af3113-18b5-4da8-af57-bdf37a6693aa	3748b1f7-b674-47ca-9ded-d011b16bbf7b	\N
24	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"caption": "archive"}	53	2021-09-22 14:50:50.411942+00	16d789c1-1b4e-4815-b70c-4ef060e90884	14af3113-18b5-4da8-af57-bdf37a6693aa	9dc0a032-90d6-4638-956e-9cd64cd2900c	\N
2	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"schema": {"type": "object", "required": ["forClass", "schema"], "properties": {"schema": {"type": "object"}, "forClass": {"type": "string"}, "parentList": {"type": "array", "items": {"type": "string"}}}}, "version": 1, "forClass": "jsonschema", "parentList": []}	32	2021-09-22 14:50:50.411942+00	16d789c1-1b4e-4815-b70c-4ef060e90884	5362d59b-82a1-4c7c-8ec3-07c256009fb0	5362d59b-82a1-4c7c-8ec3-07c256009fb0	\N
50	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"schema": {"type": "object", "required": ["subject", "type", "object"], "properties": {"tags": {"type": "array", "items": {"type": "string"}}, "type": {"type": "string", "enum ": ["params"]}, "object": {"type": "string", "pattern": "[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}"}, "disable": {"type": "boolean", "default": false}, "subject": {"type": "string", "pattern": "[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}"}}}, "version": "1", "forClass": "Relationship", "parentList": []}	27	2021-09-22 14:53:04.158111+00	16d789c1-1b4e-4815-b70c-4ef060e90884	5362d59b-82a1-4c7c-8ec3-07c256009fb0	2d054574-8f7a-4a9a-a3b3-0400ad9d0489	\N
4	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"schema": {"type": "object", "required": [], "properties": {"tags": {"type": "array", "items": {"type": "string"}}, "disable": {"type": "boolean", "default": false}}}, "version": 1, "forClass": "RecladaObject", "parentList": []}	31	2021-09-22 14:50:50.411942+00	16d789c1-1b4e-4815-b70c-4ef060e90884	5362d59b-82a1-4c7c-8ec3-07c256009fb0	ab9ab26c-8902-43dd-9f1a-743b14a89825	\N
20	3748b1f7-b674-47ca-9ded-d011b16bbf7b	{"schema": {"type": "object", "required": ["caption"], "properties": {"tags": {"type": "array", "items": {"type": "string"}}, "caption": {"type": "string"}, "disable": {"type": "boolean", "default": false}}}, "version": 1, "forClass": "ObjectStatus", "parentList": []}	11	2021-09-22 14:50:50.411942+00	16d789c1-1b4e-4815-b70c-4ef060e90884	5362d59b-82a1-4c7c-8ec3-07c256009fb0	14af3113-18b5-4da8-af57-bdf37a6693aa	\N
\.


--
-- Name: component_object_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.component_object_id_seq', 627, true);


--
-- Name: meta_data_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.meta_data_id_seq', 126, true);


--
-- Name: t_dbg_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.t_dbg_id_seq', 24, true);


--
-- Name: ver_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.ver_id_seq', 3, true);


--
-- Name: object_id_seq; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.object_id_seq', 1162, true);


--
-- Name: transaction_id; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.transaction_id', 612, true);


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
-- Name: relationship_type_subject_object_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX relationship_type_subject_object_index ON reclada.object USING btree (((attributes ->> 'type'::text)), (((attributes ->> 'subject'::text))::uuid), status, (((attributes ->> 'object'::text))::uuid)) WHERE (((attributes ->> 'subject'::text) IS NOT NULL) AND ((attributes ->> 'object'::text) IS NOT NULL));


--
-- Name: transaction_id_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX transaction_id_index ON reclada.object USING btree (transaction_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--



--
-- Name: FUNCTION invoke(function_name aws_commons._lambda_function_arn_1, payload json, invocation_type text, log_type text, context json, qualifier character varying, OUT status_code integer, OUT payload json, OUT executed_version text, OUT log_result text); Type: ACL; Schema: aws_lambda; Owner: -
--



--
-- Name: FUNCTION invoke(function_name aws_commons._lambda_function_arn_1, payload jsonb, invocation_type text, log_type text, context jsonb, qualifier character varying, OUT status_code integer, OUT payload jsonb, OUT executed_version text, OUT log_result text); Type: ACL; Schema: aws_lambda; Owner: -
--



--
-- Name: FUNCTION invoke(function_name text, payload json, region text, invocation_type text, log_type text, context json, qualifier character varying, OUT status_code integer, OUT payload json, OUT executed_version text, OUT log_result text); Type: ACL; Schema: aws_lambda; Owner: -
--



--
-- Name: FUNCTION invoke(function_name text, payload jsonb, region text, invocation_type text, log_type text, context jsonb, qualifier character varying, OUT status_code integer, OUT payload jsonb, OUT executed_version text, OUT log_result text); Type: ACL; Schema: aws_lambda; Owner: -
--



--
-- Name: v_class_lite; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_class_lite;


--
-- Name: v_object_status; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_object_status;


--
-- Name: v_user; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_user;


--
-- PostgreSQL database dump complete
--

