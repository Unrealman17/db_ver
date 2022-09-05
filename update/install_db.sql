-- version = 2
-- 2022-09-05 09:19:13.688488--
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
-- Name: api; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA api;


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
-- Name: reclada_notification; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_notification;


--
-- Name: reclada_object; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_object;


--
-- Name: reclada_revision; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_revision;


--
-- Name: reclada_storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_storage;


--
-- Name: reclada_user; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reclada_user;


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: dp_bhvr; Type: TYPE; Schema: reclada; Owner: -
--

CREATE TYPE reclada.dp_bhvr AS ENUM (
    'Replace',
    'Update',
    'Reject',
    'Copy',
    'Insert',
    'Merge'
);


--
-- Name: auth_get_login_url(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.auth_get_login_url(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    base_url VARCHAR;
    client_id VARCHAR;
BEGIN
    SELECT oidc_url, oidc_client_id INTO base_url, client_id
        FROM reclada.auth_setting;
    IF base_url IS NULL THEN
        RETURN jsonb_build_object('login_url', NULL);
    ELSE
        RETURN jsonb_build_object('login_url', format(
            '%s/auth?client_id=%s&response_type=code',
            base_url, client_id
        ));
    END IF;
END;
$$;


--
-- Name: hello_world(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.hello_world(data jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'Hello, world!';
$$;


--
-- Name: hello_world(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.hello_world(data text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'Hello, world!';
$$;


--
-- Name: reclada_object_create(jsonb, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_create(data jsonb, ver text DEFAULT '1'::text, draft text DEFAULT 'false'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    data_jsonb       jsonb;
    class            text;
    user_info        jsonb;
    attrs            jsonb;
    data_to_create   jsonb = '[]'::jsonb;
    result           jsonb;
    _need_flat       bool := false;
    _draft           bool;
    _guid            uuid;
    _f_name          text := 'api.reclada_object_create';
BEGIN

    _draft := draft != 'false';

    IF (jsonb_typeof(data) != 'array') THEN
        data := '[]'::jsonb || data;
    END IF;

    FOR data_jsonb IN SELECT jsonb_array_elements(data) LOOP

        _guid := CASE ver
                        when '1'
                            then data_jsonb->>'GUID'
                        when '2'
                            then data_jsonb->>'{GUID}'
                    end;
        if _draft then
            if _guid is null then
                perform reclada.raise_exception('GUID is required.',_f_name);
            end if;
            INSERT into reclada.draft(guid,data)
                values(_guid,data_jsonb);
        else

             class := CASE ver
                            when '1'
                                then data_jsonb->>'class'
                            when '2'
                                then data_jsonb->>'{class}'
                        end;

            IF (class IS NULL) THEN
                RAISE EXCEPTION 'The reclada object class is not specified (api)';
            END IF;

            SELECT reclada_user.auth_by_token(data_jsonb->>'accessToken') INTO user_info;
            data_jsonb := data_jsonb - 'accessToken';

            IF (NOT(reclada_user.is_allowed(user_info, 'create', class))) THEN
                RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'create', class;
            END IF;
            
            if ver = '2' then
                _need_flat := true;
                with recursive j as 
                (
                    select  row_number() over() as id,
                            key,
                            value 
                        from jsonb_each(data_jsonb)
                            where key like '{%}'
                ),
                inn as 
                (
                    SELECT  row_number() over(order by s.id,j.id) rn,
                            j.id,
                            s.id sid,
                            s.d,
                            ARRAY (
                                SELECT UNNEST(arr.v) 
                                LIMIT array_position(arr.v, s.d)
                            ) as k
                        FROM j
                        left join lateral
                        (
                            select id, d ,max(id) over() mid
                            from
                            (
                                SELECT  row_number() over() as id, 
                                        d
                                    from regexp_split_to_table(substring(j.key,2,char_length(j.key)-2),',') d 
                            ) t
                        ) s on s.mid != s.id
                        join lateral
                        (
                            select regexp_split_to_array(substring(j.key,2,char_length(j.key)-2),',') v
                        ) arr on true
                            where d is not null
                ),
                src as
                (
                    select  reclada.jsonb_deep_set('{}'::jsonb,('{'|| i.d ||'}')::text[],'{}'::jsonb) r,
                            i.rn
                        from inn i
                            where i.rn = 1
                    union
                    select  reclada.jsonb_deep_set(
                                s.r,
                                i.k,
                                '{}'::jsonb
                            ) r,
                            i.rn
                        from src s
                        join inn i
                            on s.rn + 1 = i.rn
                ),
                tmpl as 
                (
                    select r v
                        from src
                        ORDER BY rn DESC
                        limit 1
                ),
                res as
                (
                    SELECT jsonb_set(
                            (select v from tmpl),
                            j.key::text[],
                            j.value
                        ) v,
                        j.id
                        FROM j
                            where j.id = 1
                    union 
                    select jsonb_set(
                            res.v,
                            j.key::text[],
                            j.value
                        ) v,
                        j.id
                        FROM res
                        join j
                            on res.id + 1 =j.id
                )
                SELECT v 
                    FROM res
                    ORDER BY ID DESC
                    limit 1
                    into data_jsonb;
            end if;

            if data_jsonb is null then
                RAISE EXCEPTION 'JSON invalid';
            end if;
            data_to_create := data_to_create || data_jsonb;
        end if;
    END LOOP;

    if data_to_create is not  null then
        SELECT reclada_object.create(data_to_create, user_info) 
            INTO result;
    end if;
    if ver = '2' or _draft then
        RETURN '{"status":"OK"}'::jsonb;
    end if;
    RETURN result;

END;
$$;


--
-- Name: reclada_object_delete(jsonb, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_delete(data jsonb, ver text DEFAULT '1'::text, draft text DEFAULT 'false'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class         text;
    obj_id        uuid;
    user_info     jsonb;
    result        jsonb;

BEGIN

    obj_id := CASE ver
                when '1'
                    then data->>'GUID'
                when '2'
                    then data->>'{GUID}'
            end;
    IF (obj_id IS NULL) THEN
        RAISE EXCEPTION 'Could not delete object with no id';
    END IF;

    if draft != 'false' then
        delete from reclada.draft 
            where guid = obj_id;
        
    else

        class := CASE ver
                        when '1'
                            then data->>'class'
                        when '2'
                            then data->>'{class}'
                    end;
        IF (class IS NULL) THEN
            RAISE EXCEPTION 'reclada object class not specified';
        END IF;

        data := data || ('{"GUID":"'|| obj_id ||'","class":"'|| class ||'"}')::jsonb;

        SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
        data := data - 'accessToken';

        IF (NOT(reclada_user.is_allowed(user_info, 'delete', class))) THEN
            RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'delete', class;
        END IF;

        SELECT reclada_object.delete(data, user_info) INTO result;

    end if;

    if ver = '2' or draft != 'false' then 
        RETURN '{"status":"OK"}'::jsonb;
    end if;

    RETURN result;

END;
$$;


--
-- Name: reclada_object_get_transaction_id(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_get_transaction_id(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
    return reclada_object.get_transaction_id(data);
END;
$$;


--
-- Name: reclada_object_list(jsonb, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_list(data jsonb DEFAULT NULL::jsonb, ver text DEFAULT '1'::text, draft text DEFAULT 'false'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _class              text;
    user_info           jsonb;
    result              jsonb;
    _filter             jsonb;
    _guid               uuid;
BEGIN

    if draft != 'false' then
        return array_to_json
            (
                array
                (
                    SELECT o.data 
                        FROM reclada.draft o
                            where id = 
                                (
                                    select max(id) 
                                        FROM reclada.draft d
                                            where o.guid = d.guid
                                )
                            -- and o.user = user_info->>'guid'
                )
            )::jsonb;
    end if;

    _class := CASE ver
                when '1'
                    then data->>'class'
                when '2'
                    then data->>'{class}'
            end;
    IF(_class IS NULL) THEN
        RAISE EXCEPTION 'reclada object class not specified';
    END IF;

    _guid := CASE ver
        when '1'
            then data->>'GUID'
        when '2'
            then data->>'{GUID}'
    end;

    _filter = data->'filter';

    if _guid is not null then
        SELECT format(  '{
                            "operator":"AND",
                            "value":[
                                {
                                    "operator":"=",
                                    "value":["{class}","%s"]
                                },
                                {
                                    "operator":"=",
                                    "value":["{GUID}","%s"]
                                }
                            ]
                        }',
                    _class,
                    _guid
                )::jsonb 
            INTO _filter;

    ELSEIF _filter IS NOT NULL THEN
        SELECT format(  '{
                            "operator":"AND",
                            "value":[
                                {
                                    "operator":"=",
                                    "value":["{class}","%s"]
                                },
                                %s
                            ]
                        }',
                _class,
                _filter
            )::jsonb 
            INTO _filter;
    ELSEIF ver = '2' then
        SELECT format( '{
                            "operator":"=",
                            "value":["{class}","%s"]
                        }',
                _class
            )::jsonb 
            INTO _filter;
    END IF;
    
    IF _filter IS NOT NULL THEN
        data := Jsonb_set(data,'{filter}', _filter);
    END IF;

    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'list', _class))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'list', _class;
    END IF;

    SELECT reclada_object.list(data, true, ver) 
        INTO result;
    RETURN result;

END;
$$;


--
-- Name: reclada_object_list_add(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_list_add(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class          text;
    obj_id         uuid;
    user_info      jsonb;
    field_value    jsonb;
    values_to_add  jsonb;
    result         jsonb;

BEGIN

    class := data->>'class';
    IF (class IS NULL) THEN
        RAISE EXCEPTION 'The reclada object class is not specified';
    END IF;

    obj_id := (data->>'GUID')::uuid;
    IF (obj_id IS NULL) THEN
        RAISE EXCEPTION 'There is no GUID';
    END IF;

    field_value := data->'field';
    IF (field_value IS NULL) THEN
        RAISE EXCEPTION 'There is no field';
    END IF;

    values_to_add := data->'value';
    IF (values_to_add IS NULL OR values_to_add = 'null'::jsonb) THEN
        RAISE EXCEPTION 'The value should not be null';
    END IF;

    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'list_add', class))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'list_add', class;
    END IF;

    SELECT reclada_object.list_add(data) INTO result;
    RETURN result;

END;
$$;


--
-- Name: reclada_object_list_drop(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_list_drop(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class           text;
    obj_id          uuid;
    user_info       jsonb;
    field_value     jsonb;
    values_to_drop  jsonb;
    result          jsonb;

BEGIN

	class := data->>'class';
	IF (class IS NULL) THEN
		RAISE EXCEPTION 'The reclada object class is not specified';
	END IF;

	obj_id := (data->>'GUID')::uuid;
	IF (obj_id IS NULL) THEN
		RAISE EXCEPTION 'There is no GUID';
	END IF;

	field_value := data->'field';
	IF (field_value IS NULL OR field_value = 'null'::jsonb) THEN
		RAISE EXCEPTION 'There is no field';
	END IF;

	values_to_drop := data->'value';
	IF (values_to_drop IS NULL OR values_to_drop = 'null'::jsonb) THEN
		RAISE EXCEPTION 'The value should not be null';
	END IF;

    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'list_add', class))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'list_add', class;
    END IF;

    SELECT reclada_object.list_drop(data) INTO result;
    RETURN result;

END;
$$;


--
-- Name: reclada_object_list_related(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_list_related(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class          text;
    obj_id         uuid;
    field          jsonb;
    related_class  jsonb;
    user_info      jsonb;
    result         jsonb;

BEGIN
    class := data->>'class';
    IF (class IS NULL) THEN
        RAISE EXCEPTION 'The reclada object class is not specified';
    END IF;

    obj_id := (data->>'GUID')::uuid;
    IF (obj_id IS NULL) THEN
        RAISE EXCEPTION 'The object GUID is not specified';
    END IF;

    field := data->'field';
    IF (field IS NULL) THEN
        RAISE EXCEPTION 'The object field is not specified';
    END IF;

    related_class := data->'relatedClass';
    IF (related_class IS NULL) THEN
        RAISE EXCEPTION 'The related class is not specified';
    END IF;

    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'list_related', class))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'list_related', class;
    END IF;

    SELECT reclada_object.list_related(data) INTO result;

    RETURN result;

END;
$$;


--
-- Name: reclada_object_update(jsonb, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reclada_object_update(data jsonb, ver text DEFAULT '1'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class         text;
    objid         uuid;
    attrs         jsonb;
    user_info     jsonb;
    result        jsonb;
    _need_flat    bool := false;

BEGIN

    class := CASE ver
            when '1'
                then data->>'class'
            when '2'
                then data->>'{class}'
        end;

    IF (class IS NULL) THEN
        RAISE EXCEPTION 'reclada object class not specified';
    END IF;

    objid := CASE ver
            when '1'
                then data->>'GUID'
            when '2'
                then data->>'{GUID}'
        end;
    IF (objid IS NULL) THEN
        RAISE EXCEPTION 'Could not update object with no GUID';
    END IF;
    
    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'update', class))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to % %', 'update', class;
    END IF;

    if ver = '2' then

        with recursive j as 
        (
            select  row_number() over() as id,
                    key,
                    value 
                from jsonb_each(data)
                    where key like '{%}'
        ),
        t as
        (
            select  j.id    , 
                    j.key   , 
                    j.value , 
                    o.data
                from reclada.v_object o
                join j
                    on true
                    where o.obj_id = 
                        (
                            select (j.value#>>'{}')::uuid 
                                from j where j.key = '{GUID}'
                        )
        ),
        r as 
        (
            select id,key,value,jsonb_set(t.data,t.key::text[],t.value) as u, t.data
                from t
                    where id = 1
            union
            select t.id,t.key,t.value,jsonb_set(r.u   ,t.key::text[],t.value) as u, t.data
                from r
                JOIN t
                    on t.id-1 = r.id
        )
        select r.u
            from r
                where id = (select max(j.id) from j)
            INTO data;
    end if;
    -- raise notice '%', data#>>'{}';
    SELECT reclada_object.update(data, user_info) INTO result;

    if ver = '2' then
        RETURN '{"status":"OK"}'::jsonb;
    end if;
    return result;
END;
$$;


--
-- Name: storage_generate_presigned_get(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.storage_generate_presigned_get(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    object_data  jsonb;
    object_id    uuid;
    result       jsonb;
    user_info    jsonb;
    context      jsonb;

BEGIN
    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'generate presigned get', ''))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to %', 'generate presigned get';
    END IF;

    -- TODO: check user's permissions for reclada object access?
    object_id := data->>'objectId';
    SELECT reclada_object.list(format(
        '{"class": "File", "attributes": {}, "GUID": "%s"}',
        object_id
    )::jsonb) -> 0 INTO object_data;

    IF (object_data IS NULL) THEN
		RAISE EXCEPTION 'There is no object with such id';
	END IF;

    SELECT attrs
    FROM reclada.v_active_object
    WHERE class_name = 'Context'
    ORDER BY id DESC
    LIMIT 1
    INTO context;

    SELECT payload
    FROM aws_lambda.invoke(
        aws_commons.create_lambda_function_arn(
            context->>'Lambda',
            context->>'Region'
            ),
        format('{
            "type": "get",
            "uri": "%s",
            "expiration": 3600}',
            object_data->'attributes'->>'uri'
            )::jsonb)
    INTO result;

    RETURN result;
END;
$$;


--
-- Name: storage_generate_presigned_post(jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.storage_generate_presigned_post(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    user_info    jsonb;
    object_name  varchar;
    file_type    varchar;
    file_size    varchar;
    context      jsonb;
    bucket_name  varchar;
    url          varchar;
    result       jsonb;

BEGIN
    SELECT reclada_user.auth_by_token(data->>'accessToken') INTO user_info;
    data := data - 'accessToken';

    IF (NOT(reclada_user.is_allowed(user_info, 'generate presigned post', ''))) THEN
        RAISE EXCEPTION 'Insufficient permissions: user is not allowed to %', 'generate presigned post';
    END IF;

    object_name := data->>'objectName';
    file_type := data->>'fileType';
    file_size := data->>'fileSize';

    IF (object_name IS NULL) OR (file_type IS NULL) OR (file_size IS NULL) THEN
        RAISE EXCEPTION 'Parameters objectName, fileType and fileSize must be present';
    END IF;

    SELECT attrs
    FROM reclada.v_active_object
    WHERE class_name = 'RuntimeContext'
    ORDER BY id DESC
    LIMIT 1
    INTO context;

    bucket_name := data->>'bucketName';

    SELECT payload::jsonb
    FROM aws_lambda.invoke(
        aws_commons.create_lambda_function_arn(
                context->>'Lambda',
                context->>'Region'
        ),
        format('{
            "type": "post",
            "fileName": "%s",
            "fileType": "%s",
            "fileSize": "%s",
            "bucketName": "%s",
            "expiration": 3600}',
            object_name,
            file_type,
            file_size,
            bucket_name
            )::jsonb)
    INTO url;

    result = format(
        '{"uploadUrl": %s}',
        url
    )::jsonb;

    RETURN result;
END;
$$;


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
-- Name: get_children(uuid); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_children(_obj_id uuid) RETURNS SETOF uuid
    LANGUAGE sql STABLE
    AS $$
    WITH RECURSIVE temp1 (id,obj_id,parent,class_name,level) AS (
        SELECT
            id,
            obj_id,
            parent_guid,
            class_name,
            1
        FROM reclada.v_active_object vao 
        WHERE obj_id =_obj_id
            UNION 
        SELECT
            t2.id,
            t2.obj_id,
            t2.parent_guid,
            t2.class_name,
            level+1
        FROM reclada.v_active_object t2 JOIN temp1 t1 ON t1.obj_id=t2.parent_guid
    )
    SELECT obj_id FROM temp1
$$;


--
-- Name: get_duplicates(jsonb, uuid, uuid); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_duplicates(_attrs jsonb, _class_uuid uuid, exclude_uuid uuid DEFAULT NULL::uuid) RETURNS TABLE(obj_guid uuid, dup_behavior reclada.dp_bhvr, is_cascade boolean, dup_field text)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    q text;
BEGIN
    SELECT val
    FROM reclada.v_get_duplicates_query
    LIMIT 1
        INTO q;
    q := REPLACE(q, '@#@#@attrs@#@#@',          _attrs::text);
    q := REPLACE(q, '@#@#@class_uuid@#@#@',     _class_uuid::text);
    IF exclude_uuid IS NULL THEN
        q := REPLACE(q, '@#@#@exclude_uuid@#@#@',   ''::text);    
    ELSE
        q := REPLACE(q, '@#@#@exclude_uuid@#@#@',   ' || ''AND obj_id != '''''::text || exclude_uuid::text || '''''''');
    END IF;

    EXECUTE q
        INTO q;
    
    RETURN QUERY EXECUTE q;
END;            
$$;


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
-- Name: get_transaction_id_for_import(text); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_transaction_id_for_import(fileguid text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    tran_id_    bigint;
BEGIN

    select o.transaction_id
        from reclada.v_active_object o
            where o.class_name = 'Document'
                and attrs->>'fileGUID' = fileGUID
        ORDER BY ID DESC 
        limit 1
        into tran_id_;

    if tran_id_ is not null then
        PERFORM reclada_object.delete(format('{"transactionID":%s}',tran_id_)::jsonb);
    end if;
    tran_id_ := reclada.get_transaction_id();

    return tran_id_;
END
$$;


--
-- Name: get_unifield_index_name(text[]); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.get_unifield_index_name(fields text[]) RETURNS text
    LANGUAGE sql STABLE
    AS $$
	SELECT lower(array_to_string(fields,'_'))||'_index_';
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
-- Name: load_staging(); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.load_staging() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    _data_agg jsonb;
    _batch_size bigint := 1000;
BEGIN
    FOR _data_agg IN (select jsonb_agg(vrn.data)	  
                        from (
                            select data,
                                ROUND((ROW_NUMBER()OVER()-1)/_batch_size) AS rn
                                from NEW_TABLE
                        ) vrn
                        group by vrn.rn
                     ) 
    LOOP 
        PERFORM reclada_object.create(_data_agg);
    END LOOP;
    DELETE FROM reclada.staging;
    RETURN NEW;
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
-- Name: random_string(integer); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.random_string(_length integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
    chars text[] := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
    result text := '';
    i integer := 0;
    _f_name text := 'reclada.random_string';
begin
    if _length < 0 then
        perform reclada.raise_exception('Given length cannot be less than 0', _f_name);
    end if;
    for i in 1.._length loop
        result := result || chars[1+random()*(array_length(chars, 1)-1)];
    end loop;
    return result;
end;
$$;


--
-- Name: rollback_import(text); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.rollback_import(fileguid text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    tran_id_     bigint;
    json_data   jsonb;
    tmp         jsonb;
    obj_id_     uuid;
    f_name      text;
    id_         bigint;
BEGIN
    f_name := 'reclada.rollback_import';
    select o.transaction_id
        from reclada.v_active_object o
            where o.class_name = 'Document'
                and attrs->>'fileGUID' = fileGUID
        ORDER BY ID DESC 
        limit 1
        into tran_id_;

    if tran_id_ is null then
        PERFORM reclada.raise_exception('"fileGUID": "'
                            ||fileGUID
                            ||'" not found for existing Documents',f_name);
    end if;

    delete from reclada.object where tran_id_ = transaction_id;
    
    with t as (
        select o.transaction_id
            from reclada.v_object o
                where o.class_name = 'Document'
                    and attrs->>'fileGUID' = fileGUID
            ORDER BY ID DESC 
            limit 1
    ) 
    update reclada.object o
        set status = reclada_object.get_active_status_obj_id()
        from t
            where t.transaction_id = o.transaction_id;
                    
    return 'OK';
END
$$;


--
-- Name: try_cast_int(text, integer); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.try_cast_int(p_in text, p_default integer DEFAULT NULL::integer) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    return p_in::int;
    exception when others then
        return p_default;
end;
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
-- Name: xor(boolean, boolean); Type: FUNCTION; Schema: reclada; Owner: -
--

CREATE FUNCTION reclada.xor(a boolean, b boolean) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT (a and not b) or (b and not a);
$$;


--
-- Name: listen(character varying); Type: FUNCTION; Schema: reclada_notification; Owner: -
--

CREATE FUNCTION reclada_notification.listen(channel character varying) RETURNS void
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    EXECUTE 'LISTEN ' || lower(channel);
END
$$;


--
-- Name: send(character varying, jsonb); Type: FUNCTION; Schema: reclada_notification; Owner: -
--

CREATE FUNCTION reclada_notification.send(channel character varying, payload jsonb DEFAULT NULL::jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM pg_notify(lower(channel), payload::text); 
END
$$;


--
-- Name: send_object_notification(character varying, jsonb); Type: FUNCTION; Schema: reclada_notification; Owner: -
--

CREATE FUNCTION reclada_notification.send_object_notification(event character varying, object_data jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    data            jsonb;
    message         jsonb;
    msg             jsonb;
    object_class    uuid;
    class__name     varchar;
    attrs           jsonb;
    query           text;

BEGIN
    IF (jsonb_typeof(object_data) != 'array') THEN
        object_data := '[]'::jsonb || object_data;
    END IF;

    FOR data IN SELECT jsonb_array_elements(object_data) LOOP
        object_class := (data ->> 'class')::uuid;
        select for_class
            from reclada.v_class_lite cl
                where cl.obj_id = object_class
            into class__name;

        if event is null or object_class is null then
            return;
        end if;
        
        SELECT v.data
            FROM reclada.v_active_object v
                WHERE v.class_name = 'Message'
                    AND v.attrs->>'event' = event
                    AND v.attrs->>'class' = class__name
        INTO message;

        -- raise notice '%', event || ' ' || class__name;

        IF message IS NULL THEN
            RETURN;
        END IF;

        query := format(E'select to_json(x) from jsonb_to_record($1) as x(%s)',
            (
                select string_agg(s::text || ' jsonb', ',') 
                    from jsonb_array_elements(message -> 'attributes' -> 'attrs') s
            ));
        execute query into attrs using data -> 'attributes';

        msg := jsonb_build_object(
            'objectId', data -> 'GUID',
            'class', object_class,
            'event', event,
            'attributes', attrs
        );

        perform reclada_notification.send(message #>> '{attributes, channelName}', msg);

    END LOOP;
END
$_$;


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
    res           jsonb;
    affected      uuid[];
    inserted      uuid[];
    inserted_from_draft uuid[];
    _dup_behavior reclada.dp_bhvr;
    _is_cascade   boolean;
    _uni_field    text;
    _parent_guid  uuid;
    _parent_field   text;
    skip_insert     boolean;
    notify_res      jsonb;
    _cnt             int;
    _new_parent_guid       uuid;
    _rel_type       text := 'GUID changed for dupBehavior';
    _guid_list      text;
    _component_guid uuid;
    _row_count              int;
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
                continue;
            end if;
            
            insert into dev.component_object( data, status  )
                select _data, 'create';
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

        SELECT prnt_guid, prnt_field
        FROM reclada_object.get_parent_guid(_data,_class_name)
            INTO _parent_guid,
                _parent_field;
        _obj_guid := _data->>'GUID';

        IF (_parent_guid IS NOT NULL) THEN
            SELECT
                attrs->>'object',
                attrs->>'dupBehavior',
                attrs->>'isCascade'
            FROM reclada.v_active_object
            WHERE class_name = 'Relationship'
                AND attrs->>'type'                      = _rel_type
                AND (attrs->>'subject')::uuid  = _parent_guid
                    INTO _new_parent_guid, _dup_behavior, _is_cascade;

            IF _new_parent_guid IS NOT NULL THEN
                _parent_guid := _new_parent_guid;
            END IF;
        END IF;
        
        IF EXISTS (
            SELECT 1
            FROM reclada.v_object_unifields
            WHERE class_uuid = _class_uuid
        )
        THEN
            IF (_parent_guid IS NOT NULL) THEN
                IF (_dup_behavior = 'Update' AND _is_cascade) THEN
                    SELECT count(DISTINCT obj_guid), string_agg(DISTINCT obj_guid::text, ',')
                    FROM reclada.get_duplicates(_attrs, _class_uuid)
                        INTO _cnt, _guid_list;
                    IF (_cnt >1) THEN
                        RAISE EXCEPTION 'Found more than one duplicates (GUIDs: %). Resolve conflict manually.', _guid_list;
                    ELSIF (_cnt = 1) THEN
                        SELECT DISTINCT obj_guid, is_cascade
                        FROM reclada.get_duplicates(_attrs, _class_uuid)
                            INTO _obj_guid, _is_cascade;
                        new_data := _data;
                        IF new_data->>'GUID' IS NOT NULL THEN
                            PERFORM reclada_object.create_relationship(
                                    _rel_type,
                                    _obj_guid,
                                    (new_data->>'GUID')::uuid,
                                    format('{"dupBehavior": "Update", "isCascade": %s}', _is_cascade::text)::jsonb);
                        END IF;
                        new_data := reclada_object.remove_parent_guid(new_data, _parent_field);
                        new_data = reclada_object.update_json_by_guid(_obj_guid, new_data);
                        SELECT reclada_object.update(new_data)
                            INTO res;
                        affected := array_append( affected, _obj_guid);
                        skip_insert := true;
                    END IF;
                END IF;
                IF NOT EXISTS (
                    SELECT 1
                    FROM reclada.v_active_object
                    WHERE obj_id = _parent_guid
                )
                    AND _new_parent_guid IS NULL
                THEN
                    IF (_obj_guid IS NULL) THEN
                        RAISE EXCEPTION 'GUID is required.';
                    END IF;
                    INSERT INTO reclada.draft(guid, parent_guid, data)
                        VALUES(_obj_guid, _parent_guid, _data);
                    skip_insert := true;
                END IF;
            END IF;

            IF (NOT skip_insert) THEN
                SELECT COUNT(DISTINCT obj_guid), dup_behavior, string_agg (DISTINCT obj_guid::text, ',')
                FROM reclada.get_duplicates(_attrs, _class_uuid)
                GROUP BY dup_behavior
                    INTO _cnt, _dup_behavior, _guid_list;
                IF (_cnt>1 AND _dup_behavior IN ('Update','Merge')) THEN
                    RAISE EXCEPTION 'Found more than one duplicates (GUIDs: %). Resolve conflict manually.', _guid_list;
                END IF;
                FOR _obj_guid, _dup_behavior, _is_cascade, _uni_field IN
                    SELECT obj_guid, dup_behavior, is_cascade, dup_field
                    FROM reclada.get_duplicates(_attrs, _class_uuid)
                LOOP
                    new_data := _data;
                    CASE _dup_behavior
                        WHEN 'Replace' THEN
                            IF (_is_cascade = true) THEN
                                PERFORM reclada_object.delete(format('{"GUID": "%s"}', a)::jsonb)
                                FROM reclada.get_children(_obj_guid) a;
                            ELSE
                                PERFORM reclada_object.delete(format('{"GUID": "%s"}', _obj_guid)::jsonb);
                            END IF;
                        WHEN 'Update' THEN
                            IF new_data->>'GUID' IS NOT NULL THEN
                                PERFORM reclada_object.create_relationship(
                                    _rel_type,
                                    _obj_guid,
                                    (new_data->>'GUID')::uuid,
                                    format('{"dupBehavior": "Update", "isCascade": %s}', _is_cascade::text)::jsonb);
                            END IF;
                            new_data := reclada_object.remove_parent_guid(new_data, _parent_field);
                            new_data := reclada_object.update_json_by_guid(_obj_guid, new_data);
                            SELECT reclada_object.update(new_data)
                                INTO res;
                            affected := array_append( affected, _obj_guid);
                            skip_insert := true;
                        WHEN 'Reject' THEN
                            RAISE EXCEPTION 'The object was rejected.';
                        WHEN 'Copy'    THEN
                            _attrs := _attrs || format('{"%s": "%s_%s"}', _uni_field, _attrs->> _uni_field, nextval('reclada.object_id_seq'))::jsonb;
                        WHEN 'Insert' THEN
                            -- DO nothing
                        WHEN 'Merge' THEN
                            IF new_data->>'GUID' IS NOT NULL THEN
                                PERFORM reclada_object.create_relationship(
                                        _rel_type,
                                        _obj_guid,
                                        (new_data->>'GUID')::uuid,
                                        '{"dupBehavior": "Merge"}'::jsonb
                                    );
                            END IF;
                            new_data := reclada_object.remove_parent_guid(new_data, _parent_field);
                            SELECT reclada_object.update(
                                    reclada_object.merge(
                                            new_data - 'class', 
                                            data,
                                            schema
                                        ) 
                                        || format('{"GUID": "%s"}', _obj_guid)::jsonb 
                                        || format('{"transactionID": %s}', tran_id)::jsonb
                                )
                            FROM reclada.v_active_object
                            WHERE obj_id = _obj_guid
                                INTO res;
                            affected := array_append( affected, _obj_guid);
                            skip_insert := true;
                    END CASE;
                END LOOP;
            END IF;
        END IF;
        
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
            PERFORM reclada_object.object_insert
                (
                    _class_name,
                    _obj_guid,
                    _attrs
                );

            PERFORM reclada_object.refresh_mv(_class_name);
        END IF;
    END LOOP;

    SELECT array_agg(_affected_objects->>'GUID')
    FROM (
        SELECT jsonb_array_elements(_affected_objects) AS _affected_objects
        FROM (
            SELECT reclada_object.create(data) AS _affected_objects
            FROM reclada.draft
            WHERE parent_guid = ANY (affected)
        ) a
    ) b
    WHERE _affected_objects->>'GUID' IS NOT NULL
        INTO inserted_from_draft;
    affected := affected || inserted_from_draft;    

    res := array_to_json
            (
                array
                (
                    SELECT reclada.jsonb_merge(o.data, o.default_value) AS data
                    FROM reclada.v_active_object o
                    WHERE o.obj_id = ANY (affected)
                )
            )::jsonb;

    if res = '{}'::jsonb and _component_guid is not null then 
        res = '{"message": "Installing component"}'::jsonb;
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
    
    DELETE FROM reclada.draft 
        WHERE guid = ANY (affected);

    --PERFORM reclada.update_unique_object(affected);
        
    PERFORM reclada_notification.send_object_notification
        (
            'create',
            notify_res
        );
    RETURN res;
END;
$$;


--
-- Name: create_job(text, uuid, uuid, text, text, uuid); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.create_job(_uri text, _obj_id uuid, _new_guid uuid DEFAULT NULL::uuid, _task_guid text DEFAULT NULL::text, _task_command text DEFAULT NULL::text, _pipeline_job_guid uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    func_name       text := 'reclada_object.create_job';
    _environment    text;
    _obj            jsonb;
BEGIN
    SELECT attrs->>'Environment'
        FROM reclada.v_active_object
        WHERE class_name = 'RuntimeContext'
        ORDER BY created_time DESC
        LIMIT 1
        INTO _environment;

    IF _obj_id IS NULL THEN
        PERFORM reclada.raise_exception('Object ID is blank.', func_name);
    END IF;

    _obj := format('{
                "class": "Job",
                "attributes": {
                    "task": "%s",
                    "status": "new",
                    "command": "%s",
                    "inputParameters": [{"uri": "%s"}, {"dataSourceId": "%s"}]
                    }
                }',
                    COALESCE(reclada.try_cast_uuid(_task_guid), 'c94bff30-15fa-427f-9954-d5c3c151e652'::uuid),
                    COALESCE(_task_command,'./run_pipeline.sh'),
                    _uri,
                    _obj_id::text
            )::jsonb;
    IF _new_guid IS NOT NULL THEN
        _obj := jsonb_set(_obj,'{GUID}',format('"%s"',_new_guid)::jsonb);
    END IF;

    _obj := jsonb_set(_obj,'{attributes,type}',format('"%s"',_environment)::jsonb);

    IF _pipeline_job_guid IS NOT NULL THEN
        _obj := jsonb_set(_obj,'{attributes,inputParameters}',_obj#>'{attributes,inputParameters}' || format('{"PipelineLiteJobGUID" :"%s"}',_pipeline_job_guid)::jsonb);
    END IF;
    RETURN reclada_object.create(_obj);
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
            return _res;
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

    PERFORM reclada_object.perform_trigger_function(list_id, 'delete');

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

    PERFORM reclada_notification.send_object_notification('delete', data);

    RETURN data;
END;
$$;


--
-- Name: explode_jsonb(jsonb, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.explode_jsonb(obj jsonb, addr text DEFAULT ''::text) RETURNS TABLE(f_path text, f_type text)
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
	_f_type	TEXT;
BEGIN
	_f_type := jsonb_typeof(obj);
	IF _f_type = 'object' THEN
		RETURN QUERY 
			SELECT b.f_path,b.f_type
			FROM jsonb_each(obj) a
			CROSS JOIN  reclada_object.explode_jsonb(value, addr || ',' || KEY) b;
	ELSE
		RETURN QUERY SELECT addr,_f_type;
	END IF;
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
-- Name: get_parent_guid(jsonb, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_parent_guid(_data jsonb, _class_name text) RETURNS TABLE(prnt_guid uuid, prnt_field text)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    _parent_field   text;
    _parent_guid    uuid;
BEGIN
    SELECT parent_field
    FROM reclada.v_parent_field
    WHERE for_class = _class_name
        INTO _parent_field;

    _parent_guid = reclada.try_cast_uuid(_data->>'parentGUID');
    IF (_parent_guid IS NULL AND _parent_field IS NOT NULL) THEN
        _parent_guid = reclada.try_cast_uuid(_data->'attributes'->>_parent_field);
    END IF;

    RETURN QUERY
    SELECT _parent_guid,
        _parent_field;
END;
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
-- Name: get_query_condition_filter(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_query_condition_filter(data jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    _count   INT;
    _res     TEXT;
    _f_name TEXT = 'reclada_object.get_query_condition_filter';
BEGIN

    perform reclada.validate_json(data, _f_name);
    -- TODO: to change VOLATILE -> IMMUTABLE, remove CREATE TEMP TABLE
    CREATE TEMP TABLE mytable AS
        SELECT  res.lvl              AS lvl         ,
                res.rn               AS rn          ,
                res.idx              AS idx         ,
                res.prev             AS prev        ,
                res.val              AS val         ,
                res.parsed           AS parsed      ,
                coalesce(
                    po.inner_operator,
                    op.operator
                )                   AS op           ,
                coalesce
                (
                    iop.input_type,
                    op.input_type
                )                   AS input_type   ,
                case
                    when iop.input_type is not NULL
                        then NULL
                    else
                        op.output_type
                end                 AS output_type  ,
                po.operator         AS po           ,
                po.input_type       AS po_input_type,
                iop.brackets        AS po_inner_brackets
            FROM reclada_object.parse_filter(data) res
            LEFT JOIN reclada.v_filter_available_operator op
                ON res.op = op.operator
            LEFT JOIN reclada_object.parse_filter(data) p
                on  p.lvl = res.lvl-1
                    and res.prev = p.rn
            LEFT JOIN reclada.v_filter_available_operator po
                on po.operator = p.op
            LEFT JOIN reclada.v_filter_inner_operator iop
                on iop.operator = po.inner_operator;

    PERFORM reclada.raise_exception('Operator is not allowed ', _f_name)
        FROM mytable t
            WHERE t.op IS NULL;


    UPDATE mytable u
        SET parsed = to_jsonb(p.v)
            FROM mytable t
            JOIN LATERAL
            (
                SELECT  t.parsed #>> '{}' v
            ) as pt1
                ON TRUE
            LEFT JOIN reclada.v_filter_mapping fm
                ON pt1.v = fm.pattern
            JOIN LATERAL 
            (
                SELECT replace(pt1.v,'{attributes,','{') as v
            ) as pt
                ON TRUE
            JOIN LATERAL 
            (
                SELECT CASE
                        WHEN t.op LIKE '%<@%' AND t.idx=1 AND jsonb_typeof(t.parsed)='string'
                            THEN format('(COALESCE(attrs #> ''%s'', default_value -> ''attributes'' #> ''%s'')) != ''[]''::jsonb
                            AND (COALESCE(attrs #> ''%s'', default_value -> ''attributes'' #> ''%s'')) != ''{}''::jsonb
                            AND (COALESCE(attrs #> ''%s'', default_value -> ''attributes'' #> ''%s''))',
                            pt.v, pt.v, pt.v, pt.v, pt.v, pt.v)
                        WHEN fm.repl is not NULL
                            then
                                case
                                    when t.input_type in ('TEXT')
                                        then fm.repl || '::TEXT'
                                    else '(''"''||' ||fm.repl ||'||''"'')::jsonb' -- don't use FORMAT (concat null)
                                end
                        WHEN jsonb_typeof(t.parsed) in ('number', 'boolean')
                            then
                                case
                                    when t.input_type in ('NUMERIC','INT')
                                        then pt.v
                                    else '''' || pt.v || '''::jsonb'
                                end
                        WHEN jsonb_typeof(t.parsed) = 'string'
                            then
                                case
                                    WHEN pt.v LIKE '{%}'
                                        THEN
                                            case
                                                when t.input_type = 'TEXT'
                                                    then format('(COALESCE(attrs #>> ''%s'', default_value -> ''attributes'' #>> ''%s''))', pt.v, pt.v)
                                                when t.input_type = 'JSONB' or t.input_type is null
                                                    then format('(COALESCE(attrs #> ''%s'', default_value -> ''attributes'' #> ''%s''))', pt.v, pt.v)
                                                else
                                                    format('(COALESCE(attrs #>> ''%s'', default_value -> ''attributes'' #>> ''%s''))::', pt.v, pt.v) || t.input_type
                                            end
                                    when t.input_type = 'TEXT'
                                        then ''''||REPLACE(pt.v,'''','''''')||''''
                                    when t.input_type = 'JSONB' or t.input_type is null
                                        then '''"'||REPLACE(pt.v,'''','''''')||'"''::jsonb'
                                    else ''''||REPLACE(pt.v,'''','''''')||'''::'||t.input_type
                                end
                        WHEN jsonb_typeof(t.parsed) = 'null'
                            then 'null'
                        WHEN jsonb_typeof(t.parsed) = 'array'
                            then ''''||REPLACE(pt.v,'''','''''')||'''::jsonb'
                        ELSE
                            pt.v
                    END AS v
            ) as p
                ON TRUE
            WHERE t.lvl = u.lvl
                AND t.rn = u.rn
                AND t.parsed IS NOT NULL;

    update mytable u
        set op = CASE 
                    when f.btwn
                        then ' BETWEEN '
                    else u.op -- f.inop
                end,
            parsed = format(vb.operand_format,u.parsed)::jsonb
        FROM mytable t
        join lateral
        (
            select  t.op like ' %/BETWEEN ' btwn, 
                    t.po_inner_brackets is not null inop
        ) f 
            on true
        join reclada.v_filter_between vb
            on t.op = vb.operator
            WHERE t.lvl = u.lvl
                AND t.rn = u.rn
                AND (f.btwn or f.inop);


    INSERT INTO mytable (lvl,rn)
        VALUES (0,0);

    _count := 1;

    WHILE (_count>0) LOOP
        WITH r AS 
        (
            UPDATE mytable
                SET parsed = to_json(t.converted)::JSONB 
                FROM 
                (
                    SELECT     
                            res.lvl-1 lvl,
                            res.prev rn,
                            res.op,
                            1 q,
                            case 
                                when not res.po_inner_brackets 
                                    then array_to_string(array_agg(res.parsed #>> '{}' ORDER BY res.rn), res.op) 
                                else
                                    CASE COUNT(1) 
                                        WHEN 1
                                            THEN 
                                                CASE res.output_type
                                                    when 'NUMERIC'
                                                        then format('(%s %s)::TEXT::JSONB', res.op, min(res.parsed #>> '{}') )
                                                    else 
                                                        format('(%s %s)', res.op, min(res.parsed #>> '{}') )
                                                end
                                        ELSE
                                            CASE 
                                                when res.output_type = 'TEXT'
                                                    then '(''"''||'||array_to_string(array_agg(res.parsed #>> '{}' ORDER BY res.rn), res.op) ||'||''"'')::JSONB'
                                                when res.output_type in ('NUMERIC','INT')
                                                    then '('||array_to_string(array_agg(res.parsed #>> '{}' ORDER BY res.rn), res.op) ||')::TEXT::JSONB'
                                                else
                                                    '('||array_to_string(array_agg(res.parsed #>> '{}' ORDER BY res.rn), res.op) ||')'
                                            end
                                    end
                            end AS converted
                        FROM mytable res 
                            WHERE res.parsed IS NOT NULL
                                AND res.lvl = (SELECT max(lvl)+1 FROM mytable WHERE parsed IS NULL)
                            GROUP BY  res.prev, res.op, res.lvl, res.input_type, res.output_type, res.po_inner_brackets
                ) t
                WHERE
                    t.lvl = mytable.lvl
                        AND t.rn = mytable.rn
                RETURNING 1
        )
            SELECT COUNT(1) 
                FROM r
                INTO _count;
    END LOOP;
    
    SELECT parsed #>> '{}' 
        FROM mytable
            WHERE lvl = 0 AND rn = 0
        INTO _res;
    -- perform reclada.raise_notice( _res);
    DROP TABLE mytable;
    RETURN _res;
END 
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
-- Name: get_transaction_id(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.get_transaction_id(_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    _action text;
    _res jsonb;
    _tran_id bigint;
    _guid uuid;
    _func_name text;
BEGIN
    _func_name := 'reclada_object.get_transaction_id';
    _action := _data ->> 'action';
    _guid := _data ->> 'GUID';

    if    _action = 'new' and _guid is null    
    then
        _tran_id := reclada.get_transaction_id();
    ELSIF _action is null  and _guid is not null 
    then
        select o.transaction_id 
            from reclada.v_object o
                where _guid = o.obj_id
        into _tran_id;
        if _tran_id is null 
        then
            perform reclada.raise_exception('GUID not found.',_func_name);
        end if;
    else 
        perform reclada.raise_exception('Parameter has to contain GUID or action.',_func_name);
    end if;

    RETURN format('{"transactionID":%s}',_tran_id):: jsonb;
END;
$$;


--
-- Name: is_equal(jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.is_equal(lobj jsonb, robj jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
	DECLARE
		cnt 	int;
		ltype	text;
		rtype	text;
	BEGIN
		ltype := jsonb_typeof(lobj);
		rtype := jsonb_typeof(robj);
		IF ltype != rtype THEN
			RETURN False;
		END IF;
		CASE ltype 
		WHEN 'object' THEN
			SELECT count(*) INTO cnt FROM (                     -- Using joining operators compatible with merge or hash join is obligatory
				SELECT 1                                        --    with FULL OUTER JOIN. is_equal is compatible only with NESTED LOOPS
				FROM (SELECT jsonb_each(lobj) AS rec) a         --    so I use LEFT JOIN UNION ALL RIGHT JOIN insted of FULL OUTER JOIN.
				LEFT JOIN
					(SELECT jsonb_each(robj) AS rec) b
				ON (a.rec).key = (b.rec).key AND reclada_object.is_equal((a.rec).value, (b.rec).value)  
				WHERE b.rec IS NULL
            UNION ALL 
				SELECT 1
				FROM (SELECT jsonb_each(robj) AS rec) a
				LEFT JOIN
					(SELECT jsonb_each(lobj) AS rec) b
				ON (a.rec).key = (b.rec).key AND reclada_object.is_equal((a.rec).value, (b.rec).value)  
				WHERE b.rec IS NULL
			) a;
			RETURN cnt=0;
		WHEN 'array' THEN
			SELECT count(*) INTO cnt FROM (
				SELECT 1
				FROM (SELECT jsonb_array_elements (lobj) AS rec) a
				LEFT JOIN
					(SELECT jsonb_array_elements (robj) AS rec) b
				ON reclada_object.is_equal((a.rec), (b.rec))  
				WHERE b.rec IS NULL
				UNION ALL
				SELECT 1
				FROM (SELECT jsonb_array_elements (robj) AS rec) a
				LEFT JOIN
					(SELECT jsonb_array_elements (lobj) AS rec) b
				ON reclada_object.is_equal((a.rec), (b.rec))  
				WHERE b.rec IS NULL
			) a;
			RETURN cnt=0;
		WHEN 'string' THEN
			RETURN text(lobj) = text(robj);
		WHEN 'number' THEN
			RETURN lobj::numeric = robj::numeric;
		WHEN 'boolean' THEN
			RETURN lobj::boolean = robj::boolean;
		WHEN 'null' THEN
			RETURN True;                                    -- It should be Null
		ELSE
			RETURN null;
		END CASE;
	END;
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
    _filter             jsonb;
    _object_display     jsonb;
    _order_row          jsonb;
BEGIN

    perform reclada.validate_json(data, _f_name);
    raise notice '%',data;
    if ver = '1' then
        tran_id := (data->>'transactionID')::bigint;
        _class := data->>'class';
    elseif ver = '2' then
        tran_id := (data->>'{transactionID}')::bigint;
        _class := data->>'{class}';
    end if;
    _filter = data->'filter';

    order_by_jsonb := data->'orderBy';
    IF ((order_by_jsonb IS NULL) OR
        (order_by_jsonb = 'null'::jsonb) OR
        (order_by_jsonb = '[]'::jsonb)) THEN
        
        SELECT (vod.table #> '{orderRow}') AS orderRow
            FROM reclada.v_object_display vod
            WHERE vod.class_guid = (SELECT(reclada_object.get_schema (_class)#>>'{GUID}')::uuid)
            INTO _order_row;
        IF _order_row IS NOT NULL THEN     
            SELECT jsonb_agg (
                        jsonb_build_object(
                                            'field',    replace(
                                                            replace(obf.field::text,'{',''),
                                                                '}',''
                                                        ), 
                                            'order', obf.order_by
                                        )
                            )
                FROM(
                    SELECT  je.value AS order_by, 
                            split_part (je.key, ':', 1) AS field
                        FROM jsonb_array_elements (_order_row) jae
                        CROSS JOIN jsonb_each (jae.value) je
                    ) obf
                INTO order_by_jsonb;
        ELSE
            order_by_jsonb := '[{"field": "id", "order": "ASC"}]'::jsonb;
        END IF;
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
    IF ver = '2' THEN
        _pre_query := (select val from reclada.v_ui_active_object);
        _from := 'res AS obj';
        _pre_query := REPLACE(_pre_query, '#@#@#where#@#@#'  , query_conditions);
        _pre_query := REPLACE(_pre_query, '#@#@#orderby#@#@#', order_by        );
        order_by :=  REPLACE(order_by, '{', '{"{');
        order_by :=  REPLACE(order_by, '}', '}"}'); --obj.data#>'{some_field}'  -->  obj.data#>'{"{some_field}"}'

    ELSE
        _pre_query := '';
        _from := 'reclada.v_active_object AS obj
                            WHERE #@#@#where#@#@#';
        _from := REPLACE(_from, '#@#@#where#@#@#', query_conditions  );
    END IF;
    _exec_text := _pre_query ||
                'SELECT to_jsonb(array_agg(t.data))
                    FROM 
                    (
                        SELECT '
                        || CASE
                            WHEN ver = '2'
                                THEN 'obj.data '
                            ELSE 'reclada.jsonb_merge(obj.data, obj.default_value) AS data
                                 '
                        END
                            ||
                            'FROM '
                            || _from
                            || ' 
                            ORDER BY #@#@#orderby#@#@#'
                            || CASE
                                WHEN ver = '2'
                                    THEN ''
                                ELSE
                                '
                                OFFSET #@#@#offset#@#@#
                                LIMIT #@#@#limit#@#@#'
                            END
                            || '
                    ) AS t';
    _exec_text := REPLACE(_exec_text, '#@#@#orderby#@#@#'  , order_by          );
    _exec_text := REPLACE(_exec_text, '#@#@#offset#@#@#'   , offset_           );
    _exec_text := REPLACE(_exec_text, '#@#@#limit#@#@#'    , limit_            );
    -- RAISE NOTICE 'conds: %', _exec_text;

    EXECUTE _exec_text
        INTO objects;
    objects := coalesce(objects,'[]'::jsonb);
    IF gui THEN

        if ver = '2' then
            class_uuid := coalesce(class_uuid, (objects#>>'{0,"{class}"}')::uuid);
            if class_uuid is not null then
                _class :=   (
                                select cl.for_class 
                                    from reclada.v_class_lite cl
                                        where class_uuid = cl.obj_id
                                            limit 1
                            );

                _exec_text := '
                with 
                d as ( 
                    select id_unique_object
                        FROM reclada.v_active_object obj 
                        JOIN reclada.unique_object_reclada_object as uoc
                            on uoc.id_reclada_object = obj.id
                                and #@#@#where#@#@#
                        group by id_unique_object
                ),
                dd as (
                    select distinct 
                            ''{''||f.path||''}:''||f.json_type v,
                            f.json_type
                        FROM d 
                        JOIN reclada.unique_object as uo
                            on d.id_unique_object = uo.id
                        JOIN reclada.field f
                            on f.id = ANY (uo.id_field)
                    UNION
                    SELECT  pattern||'':''|| t.v,
                            t.v
                    FROM reclada.v_filter_mapping vfm
                    CROSS JOIN LATERAL 
                    (
                        SELECT  CASE 
                                    WHEN vfm.pattern=''{transactionID}'' 
                                        THEN ''number'' 
                                    ELSE ''string'' 
                                END as v
                    ) t
                ),
                on_data as 
                (
                    select  jsonb_object_agg(
                                t.v, 
                                replace(dd.template,''#@#attrname#@#'',t.v)::jsonb 
                            ) t
                        from dd as t
                        JOIN reclada.v_default_display dd
                            on t.json_type = dd.json_type
                )
                select jsonb_set(templ.v,''{table}'', od.t || coalesce(d.table,coalesce(d.table,templ.v->''table'')))
                    from on_data od
                    join (
                        select replace(template,''#@#classname#@#'','''|| _class ||''')::jsonb v
                            from reclada.v_default_display 
                                where json_type = ''ObjectDisplay''
                                    limit 1
                    ) templ
                        on true
                    left join reclada.v_object_display d
                        on d.class_guid::text = '''|| coalesce( class_uuid::text, '' ) ||'''';

                _exec_text := REPLACE(_exec_text, '#@#@#where#@#@#', query_conditions  );
                -- raise notice '%',_exec_text;
                EXECUTE _exec_text
                    INTO _object_display;
            end if;
        end if;


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
-- Name: list_add(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.list_add(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class          text;
    objid          uuid;
    obj            jsonb;
    values_to_add  jsonb;
    field          text;
    field_value    jsonb;
    json_path      text[];
    new_obj        jsonb;
    res            jsonb;

BEGIN

    class := data->>'class';
    IF (class IS NULL) THEN
        RAISE EXCEPTION 'The reclada object class is not specified';
    END IF;

    objid := (data->>'GUID')::uuid;
    IF (objid IS NULL) THEN
        RAISE EXCEPTION 'There is no GUID';
    END IF;

    SELECT v.data
	FROM reclada.v_active_object v
	WHERE v.obj_id = objid
	INTO obj;

    IF (obj IS NULL) THEN
        RAISE EXCEPTION 'There is no object with such id';
    END IF;

    values_to_add := data->'value';
    IF (values_to_add IS NULL OR values_to_add = 'null'::jsonb) THEN
        RAISE EXCEPTION 'The value should not be null';
    END IF;

    IF (jsonb_typeof(values_to_add) != 'array') THEN
        values_to_add := format('[%s]', values_to_add)::jsonb;
    END IF;

    field := data->>'field';
    IF (field IS NULL) THEN
        RAISE EXCEPTION 'There is no field';
    END IF;
    json_path := format('{attributes, %s}', field);
    field_value := obj#>json_path;

    IF ((field_value = 'null'::jsonb) OR (field_value IS NULL)) THEN
        SELECT jsonb_set(obj, json_path, values_to_add)
        INTO new_obj;
    ELSE
        SELECT jsonb_set(obj, json_path, field_value || values_to_add)
        INTO new_obj;
    END IF;

    SELECT reclada_object.update(new_obj) INTO res;
    RETURN res;

END;
$$;


--
-- Name: list_drop(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.list_drop(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    class           text;
    objid           uuid;
    obj             jsonb;
    values_to_drop  jsonb;
    field           text;
    field_value     jsonb;
    json_path       text[];
    new_value       jsonb;
    new_obj         jsonb;
    res             jsonb;

BEGIN

	class := data->>'class';
	IF (class IS NULL) THEN
		RAISE EXCEPTION 'The reclada object class is not specified';
	END IF;

	objid := (data->>'GUID')::uuid;
	IF (objid IS NULL) THEN
		RAISE EXCEPTION 'There is no GUID';
	END IF;

    SELECT v.data
    FROM reclada.v_active_object v
    WHERE v.obj_id = objid
    INTO obj;

	IF (obj IS NULL) THEN
		RAISE EXCEPTION 'There is no object with such id';
	END IF;

	values_to_drop := data->'value';
	IF (values_to_drop IS NULL OR values_to_drop = 'null'::jsonb) THEN
		RAISE EXCEPTION 'The value should not be null';
	END IF;

	IF (jsonb_typeof(values_to_drop) != 'array') THEN
		values_to_drop := format('[%s]', values_to_drop)::jsonb;
	END IF;

	field := data->>'field';
	IF (field IS NULL) THEN
		RAISE EXCEPTION 'There is no field';
	END IF;
	json_path := format('{attributes, %s}', field);
	field_value := obj#>json_path;
	IF (field_value IS NULL OR field_value = 'null'::jsonb) THEN
		RAISE EXCEPTION 'The object does not have this field';
	END IF;

	SELECT jsonb_agg(elems)
	FROM
		jsonb_array_elements(field_value) elems
	WHERE
		elems NOT IN (
			SELECT jsonb_array_elements(values_to_drop))
	INTO new_value;

	SELECT jsonb_set(obj, json_path, coalesce(new_value, '[]'::jsonb))
	INTO new_obj;

	SELECT reclada_object.update(new_obj) INTO res;
	RETURN res;

END;
$$;


--
-- Name: list_related(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.list_related(data jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    class          text;
    objid          uuid;
    field          text;
    related_class  text;
    obj            jsonb;
    list_of_ids    jsonb;
    cond           jsonb = '{}'::jsonb;
    order_by       jsonb;
    limit_         text;
    offset_        text;
    res            jsonb;

BEGIN
    class := data->>'class';
    IF (class IS NULL) THEN
        RAISE EXCEPTION 'The reclada object class is not specified';
    END IF;

    objid := (data->>'GUID')::uuid;
    IF (objid IS NULL) THEN
        RAISE EXCEPTION 'The object GUID is not specified';
    END IF;

    field := data->>'field';
    IF (field IS NULL) THEN
        RAISE EXCEPTION 'The object field is not specified';
    END IF;

    related_class := data->>'relatedClass';
    IF (related_class IS NULL) THEN
        RAISE EXCEPTION 'The related class is not specified';
    END IF;

	SELECT v.data
	FROM reclada.v_active_object v
	WHERE v.obj_id = objid
	INTO obj;

    IF (obj IS NULL) THEN
        RAISE EXCEPTION 'There is no object with such id';
    END IF;

    list_of_ids := obj#>(format('{attributes, %s}', field)::text[]);
    IF (list_of_ids IS NULL) THEN
        RAISE EXCEPTION 'The object does not have this field';
    END IF;
    IF (jsonb_typeof(list_of_ids) != 'array') THEN
        list_of_ids := '[]'::jsonb || list_of_ids;
    END IF;

    order_by := data->'orderBy';
    IF (order_by IS NOT NULL) THEN
        cond := cond || (format('{"orderBy": %s}', order_by)::jsonb);
    END IF;

    limit_ := data->>'limit';
    IF (limit_ IS NOT NULL) THEN
        cond := cond || (format('{"limit": "%s"}', limit_)::jsonb);
    END IF;

    offset_ := data->>'offset';
    IF (offset_ IS NOT NULL) THEN
        cond := cond || (format('{"offset": "%s"}', offset_)::jsonb);
    END IF;
    
    IF (list_of_ids = '[]'::jsonb) THEN
        res := '{"number": 0, "objects": []}'::jsonb;
    ELSE
        SELECT reclada_object.list(format(
            '{"class": "%s", "attributes": {}, "GUID": {"operator": "<@", "object": %s}}',
            related_class,
            list_of_ids
            )::jsonb || cond,
            true)
        INTO res;
    END IF;

    RETURN res;

END;
$$;


--
-- Name: merge(jsonb, jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.merge(lobj jsonb, robj jsonb, schema jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
    DECLARE
        res     jsonb;
        ltype    text;
        rtype    text;
    BEGIN
        ltype := jsonb_typeof(lobj);
        rtype := jsonb_typeof(robj);
        IF (lobj IS NULL AND robj IS NOT NULL) THEN
            RETURN robj;
        END IF;
        IF (lobj IS NOT NULL AND robj IS NULL) THEN
            RETURN lobj;
        END IF;
        IF (ltype = 'null') THEN
            RETURN robj;
        END IF;
        IF (ltype != rtype) THEN
            RETURN lobj || robj;
        END IF;
        IF reclada_object.is_equal(lobj,robj) THEN
            RETURN lobj;
        END IF;
        CASE ltype 
        WHEN 'object' THEN
            SELECT jsonb_object_agg(key,val)
            FROM (
                SELECT key, reclada_object.merge(lval,rval) as val
                    FROM (                     -- Using joining operators compatible with merge or hash join is obligatory
                    SELECT (a.rec).key as key,
                        (a.rec).value AS lval,
                        (b.rec).value AS rval                                        --    with FULL OUTER JOIN. merge is compatible only with NESTED LOOPS
                    FROM (SELECT jsonb_each(lobj) AS rec) a         --    so I use LEFT JOIN UNION ALL RIGHT JOIN insted of FULL OUTER JOIN.
                    LEFT JOIN
                        (SELECT jsonb_each(robj) AS rec) b
                    ON (a.rec).key = (b.rec).key
                UNION
                    SELECT (a.rec).key as key,
                        (b.rec).value AS lval,
                        (a.rec).value AS rval
                    FROM (SELECT jsonb_each(robj) AS rec) a
                    LEFT JOIN
                        (SELECT jsonb_each(lobj) AS rec) b
                    ON (a.rec).key = (b.rec).key
                ) a
            ) b
                INTO res;
            IF schema IS NOT NULL AND NOT validate_json_schema(schema, res->'attributes') THEN
                RAISE EXCEPTION 'Objects aren''t mergeable. Solve duplicate conflicate manually.';
            END IF;
            RETURN res;
        WHEN 'array' THEN
            SELECT to_jsonb(array_agg(rec)) FROM (
                SELECT COALESCE(a.rec, b.rec) as rec
                FROM (SELECT jsonb_array_elements (lobj) AS rec) a
                LEFT JOIN
                    (SELECT jsonb_array_elements (robj) AS rec) b
                ON reclada_object.is_equal((a.rec), (b.rec))
                UNION
                SELECT COALESCE(a.rec, b.rec) as rec
                FROM (SELECT jsonb_array_elements (robj) AS rec) a
                LEFT JOIN
                    (SELECT jsonb_array_elements (lobj) AS rec) b
                ON reclada_object.is_equal((a.rec), (b.rec))
            ) a
                INTO res;
            RETURN res;
        WHEN 'string' THEN
            RETURN lobj || robj;
        WHEN 'number' THEN
            RETURN lobj || robj;
        WHEN 'boolean' THEN
            RETURN lobj || robj;
        WHEN 'null' THEN
            RETURN '{}'::jsonb;                                    -- It should be Null
        ELSE
            RETURN null;
        END CASE;
    END;
$$;


--
-- Name: need_flat(text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.need_flat(_class_name text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    select exists
        (
            select true as r
                from reclada.v_object_display d
                join reclada_object.get_guid_for_class(_class_name) tf
                    on tf.obj_id = d.class_guid
                where d.table is not null
        )
$$;


--
-- Name: object_insert(text, uuid, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.object_insert(_class_name text, _obj_id uuid, attributes jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    _exec_text          text ;
    _where              text ;
    _fields             text ;
    _pipeline_lite      jsonb;
    _task               jsonb;
    _dataset_guid       uuid ;
    _new_guid           uuid ;
    _pipeline_job_guid  uuid ;
    _stage              text ;
    _uri                text ;
    _dataset2ds_type    text = 'defaultDataSet to DataSource';
    _f_name             text = 'reclada_object.object_insert';
    _trigger_guid       uuid;
    _function_name      text;
    _function_guid      uuid;
    _query              text;
    _current_id         bigint;
    _current_id_array   bigint[];               
BEGIN
    IF _class_name in ('DataSource','File') THEN

        _uri := attributes->>'uri';

        SELECT v.obj_id
            FROM reclada.v_active_object v
            WHERE v.class_name = 'DataSet'
                and v.attrs->>'name' = 'defaultDataSet'
            INTO _dataset_guid;

        IF (_dataset_guid IS NULL) THEN
            RAISE EXCEPTION 'Can''t found defaultDataSet';
        END IF;
        PERFORM reclada_object.create_relationship(_dataset2ds_type, _obj_id, _dataset_guid);
        IF _uri LIKE '%inbox/jobs/%' THEN
            PERFORM reclada_object.create_job(_uri, _obj_id);
        ELSE
            
            SELECT data 
                FROM reclada.v_active_object
                    WHERE class_name = 'PipelineLite'
                        LIMIT 1
                INTO _pipeline_lite;
            _new_guid := public.uuid_generate_v4();
            IF _uri LIKE '%inbox/pipelines/%/%' THEN
                
                _stage := SPLIT_PART(
                                SPLIT_PART(_uri,'inbox/pipelines/',2),
                                '/',
                                2
                            );
                _stage = replace(_stage,'.json','');
                SELECT data 
                    FROM reclada.v_active_object o
                        where o.class_name = 'Task'
                            and o.obj_id = (_pipeline_lite #>> ('{attributes,tasks,'||_stage||'}')::text[])::uuid
                    into _task;
                
                _pipeline_job_guid = reclada.try_cast_uuid(
                                        SPLIT_PART(
                                            SPLIT_PART(_uri,'inbox/pipelines/',2),
                                            '/',
                                            1
                                        )
                                    );
                IF _pipeline_job_guid IS NULL THEN
                    perform reclada.raise_exception('PIPELINE_JOB_GUID not found',_f_name);
                END IF;
                
                SELECT  data #>> '{attributes,inputParameters,0,uri}',
                        (data #>> '{attributes,inputParameters,1,dataSourceId}')::uuid
                    FROM reclada.v_active_object o
                        WHERE o.obj_id = _pipeline_job_guid
                    INTO _uri, _obj_id;

            ELSE
                SELECT data 
                    FROM reclada.v_active_object o
                        WHERE o.class_name = 'Task'
                            AND o.obj_id = (_pipeline_lite #>> '{attributes,tasks,0}')::uuid
                    INTO _task;
                IF _task IS NOT NULL THEN
                    _pipeline_job_guid := _new_guid;
                END IF;
            END IF;
            
            PERFORM reclada_object.create_job(
                _uri,
                _obj_id,
                _new_guid,
                _task->>'GUID',
                _task-> 'attributes' ->>'command',
                _pipeline_job_guid
            );
        END IF;
    
    ELSIF _class_name = 'Index' then
        _exec_text := 'DROP INDEX IF EXISTS reclada.#@#@#name#@#@#;
            CREATE INDEX #@#@#name#@#@# ON reclada.object USING #@#@#method#@#@# (#@#@#fields#@#@#) #@#@#where#@#@#;';
        _exec_text := REPLACE(_exec_text, '#@#@#name#@#@#'   , attributes->>'name'                      );
        _exec_text := REPLACE(_exec_text, '#@#@#method#@#@#' , coalesce(attributes->>'method' ,'btree') );

        _fields :=  (
                        select string_agg(value,'#@#@#sep#@#@#')
                            from jsonb_array_elements_text(attributes->'fields')
                    );
        _where := coalesce(attributes->>'wherePredicate','');

        if _where != '' then
            if _where = 'IS NOT NULL' then
                _where := REPLACE(_fields,'#@#@#sep#@#@#', ' IS NOT NULL OR ') || ' IS NOT NULL';
            end if;
            _where := 'WHERE ' || _where;
        end if;

        _fields := REPLACE(_fields,'#@#@#sep#@#@#', ' , ');

        _exec_text := REPLACE(_exec_text, '#@#@#fields#@#@#' , _fields);
        _exec_text := REPLACE(_exec_text, '#@#@#where#@#@#'  , _where );
        EXECUTE _exec_text;

    ELSIF _class_name = 'View' then

        _exec_text := 'DROP VIEW IF EXISTS reclada.#@#@#name#@#@#;
            CREATE VIEW reclada.#@#@#name#@#@# as #@#@#query#@#@#;';
        _exec_text := REPLACE(_exec_text, '#@#@#name#@#@#'   , attributes->>'name' );
        _exec_text := REPLACE(_exec_text, '#@#@#query#@#@#' , attributes->>'query' );

        EXECUTE _exec_text;

    ELSIF _class_name IN ('Function', 'DBTriggerFunction') then

        _exec_text := 'DROP FUNCTION IF EXISTS reclada.#@#@#name#@#@#;
            CREATE FUNCTION reclada.#@#@#name#@#@#
            (
                #@#@#parameters#@#@#
            )
            RETURNS #@#@#returns#@#@# AS '||chr(36)||chr(36)||'
            DECLARE
                #@#@#declare#@#@#
            BEGIN   
                #@#@#body#@#@#
            END;
            '||chr(36)||chr(36)||' LANGUAGE ''plpgsql'' VOLATILE;';

        _exec_text := REPLACE(_exec_text, '#@#@#name#@#@#'      , attributes->>'name'   );
        _exec_text := REPLACE(_exec_text, '#@#@#returns#@#@#'   , attributes->>'returns');
        _exec_text := REPLACE(_exec_text, '#@#@#body#@#@#'      , attributes->>'body'   );

        _exec_text := REPLACE(
                _exec_text, '#@#@#parameters#@#@#', 
                (SELECT  STRING_AGG(
                            (el.value->>'name')
                                || ' '
                                || (el.value->>'type'),
                            ',' || chr(10)
                        )
                    FROM jsonb_array_elements(attributes->'parameters') el) 
            );

        _exec_text := REPLACE(
                _exec_text, '#@#@#declare#@#@#', 
                (SELECT  STRING_AGG(
                            (el.value->>'name')
                                || ' '
                                || (el.value->>'type')
                                || ';', 
                            chr(10)
                        )
                    FROM jsonb_array_elements(attributes->'declare') el )
            );

        EXECUTE _exec_text;
    END IF;
    SELECT vab.id 
        FROM reclada.v_active_object vab
            WHERE vab.obj_id = _obj_id
        INTO _current_id;
    
    _current_id_array := ARRAY[_current_id];
    
    PERFORM reclada_object.perform_trigger_function(_current_id_array, 'insert');

END;
$$;


--
-- Name: parse_filter(jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.parse_filter(data jsonb) RETURNS TABLE(lvl integer, rn bigint, idx bigint, op text, prev bigint, val jsonb, parsed jsonb)
    LANGUAGE sql IMMUTABLE
    AS $$
    WITH RECURSIVE f AS 
    (
        SELECT data AS v
    ),
    pr AS 
    (
        SELECT 	format(' %s ',f.v->>'operator') AS op, 
                val.v AS val,
                1 AS lvl,
                row_number() OVER(ORDER BY idx) AS rn,
                val.idx idx,
                0::BIGINT prev
            FROM f, jsonb_array_elements(f.v->'value') WITH ordinality AS val(v, idx)
    ),
    res AS
    (	
        SELECT 	pr.lvl	,
                pr.rn	,
                pr.idx  ,
                pr.op	,
                pr.prev ,
                pr.val	,
                CASE jsonb_typeof(pr.val) 
                    WHEN 'object'	
                        THEN NULL
                    ELSE pr.val
                END AS parsed
            FROM pr
            WHERE prev = 0 
                AND lvl = 1
        UNION ALL
        SELECT 	ttt.lvl	,
                ROW_NUMBER() OVER(ORDER BY ttt.idx) AS rn,
                ttt.idx,
                ttt.op	,
                ttt.prev,
                ttt.val ,
                CASE jsonb_typeof(ttt.val) 
                    WHEN 'object'	
                        THEN NULL
                    ELSE ttt.val
                end AS parsed
            FROM
            (
                SELECT 	res.lvl + 1 AS lvl,
                        format(' %s ',res.val->>'operator') AS op,
                        res.rn AS prev	,
                        val.v  AS val,
                        val.idx
                    FROM res, 
                         jsonb_array_elements(res.val->'value') WITH ordinality AS val(v, idx)
            ) ttt
    )
    SELECT 	r.lvl	,
            r.rn	,
            r.idx   ,
            case upper(r.op) 
                when ' XOR '
                    then ' OPERATOR(reclada.##) ' 
                else upper(r.op) 
            end,
            r.prev  ,
            r.val	,
            r.parsed
        FROM res r
$$;


--
-- Name: perform_trigger_function(bigint[], text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.perform_trigger_function(_list_id bigint[], _trigger_type text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    _query          text ;           
BEGIN
    SELECT string_agg(sbq.subquery, '')
	    FROM ( 
            SELECT  'SELECT reclada.' 
                    || vtf.function_name 
                    || '(' 
                    || idcl.id
                    || ');'
                    || chr(10) AS subquery
                FROM reclada.v_trigger vt
                    JOIN reclada.v_db_trigger_function vtf
                        ON vt.function_guid = vtf.function_guid
                    CROSS JOIN (SELECT vo.id, vo.class_name 
                            FROM reclada.v_object vo
                                WHERE vo.id IN (SELECT unnest(_list_id))
                        ) idcl
                        WHERE vt.trigger_type = _trigger_type
                            AND idcl.class_name IN (SELECT jsonb_array_elements_text(vt.for_classes))
            ) sbq
        INTO _query;

    IF _query IS NOT NULL THEN
        raise notice '(%)', _query;
        EXECUTE _query;
    END IF;
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
            REFRESH MATERIALIZED VIEW reclada.v_object_unifields;
        WHEN 'All' THEN
            REFRESH MATERIALIZED VIEW reclada.v_object_status;
            REFRESH MATERIALIZED VIEW reclada.v_user;
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
            REFRESH MATERIALIZED VIEW reclada.v_object_unifields;
        ELSE
            NULL;
    END CASE;
END;
$$;


--
-- Name: remove_parent_guid(jsonb, text); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.remove_parent_guid(_data jsonb, parent_field text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
    BEGIN
        IF (parent_field IS NOT NULL) THEN
            _data := _data #- format('{attributes,%s}',parent_field)::text[];
        END IF;
        _data := _data - 'parent_guid';
        _data := _data - 'GUID';
        RETURN _data;
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
    _parent_field text;
    _obj_guid     uuid;
    _dup_behavior reclada.dp_bhvr;
    _uni_field    text;
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
    SELECT reclada_revision.create(user_info->>'sub', branch, _obj_id, _tran_id) 
        INTO revid;

    SELECT prnt_guid, prnt_field
    FROM reclada_object.get_parent_guid(_data,_class_name)
        INTO _parent_guid,
            _parent_field;

    IF (_parent_guid IS NULL) THEN
        _parent_guid := old_obj->>'parentGUID';
    END IF;
    
    IF EXISTS (
        SELECT 1
        FROM reclada.v_object_unifields
        WHERE class_uuid=_class_uuid
    )
    THEN
        SELECT COUNT(DISTINCT obj_guid), dup_behavior, string_agg(DISTINCT obj_guid::text, ',')
        FROM reclada.get_duplicates(_attrs, _class_uuid, _obj_id)
        GROUP BY dup_behavior
            INTO _cnt, _dup_behavior, _guid_list;
        IF (_cnt>1 AND _dup_behavior IN ('Update','Merge')) THEN
            RAISE EXCEPTION 'Found more than one duplicates (GUIDs: %). Resolve conflict manually.', _guid_list;
        END IF;
        FOR _obj_guid, _dup_behavior, _uni_field IN (
                SELECT obj_guid, dup_behavior, dup_field
                FROM reclada.get_duplicates(_attrs, _class_uuid, _obj_id)
            ) LOOP
            IF _dup_behavior IN ('Update','Merge') THEN
                UPDATE reclada.object o
                    SET status = reclada_object.get_archive_status_obj_id()
                WHERE o.GUID = _obj_guid
                    AND status != reclada_object.get_archive_status_obj_id();
            END IF;
            CASE _dup_behavior
                WHEN 'Replace' THEN
                    PERFORM reclada_object.delete(format('{"GUID": "%s"}', _obj_guid)::jsonb);
                WHEN 'Update' THEN                    
                    _data := reclada_object.remove_parent_guid(_data, _parent_field);
                    _data := reclada_object.update_json_by_guid(_obj_guid, _data);
                    RETURN reclada_object.update(_data);
                WHEN 'Reject' THEN
                    RAISE EXCEPTION 'Duplicate found (GUID: %). Object rejected.', _obj_guid;
                WHEN 'Copy'    THEN
                    _attrs = _attrs || format('{"%s": "%s_%s"}', _uni_field, _attrs->> _uni_field, nextval('reclada.object_id_seq'))::jsonb;
                    IF (NOT(public.validate_json_schema(schema, _attrs))) THEN
                        RAISE EXCEPTION 'JSON invalid: %', _attrs;
                    END IF;
                WHEN 'Insert' THEN
                    -- DO nothing
                WHEN 'Merge' THEN     
                    _data := reclada_object.remove_parent_guid(_data, _parent_field);               
                    RETURN reclada_object.update(
                        reclada_object.merge(
                            _data - 'class', 
                            vao.data, 
                            schema
                        ) || format('{"GUID": "%s"}', _obj_guid)::jsonb
                    )
                        FROM reclada.v_active_object vao
                            WHERE obj_id = _obj_guid;
            END CASE;
        END LOOP;
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

    --PERFORM reclada.update_unique_object(ARRAY[_obj_id]);

    PERFORM reclada_object.object_insert
            (
                _class_name,
                _obj_id,
                _attrs
            );
    PERFORM reclada_object.refresh_mv(_class_name);

    IF ( _class_name = 'jsonschema' AND jsonb_typeof(_attrs->'dupChecking') = 'array') THEN
        PERFORM reclada_object.refresh_mv('uniFields');
    END IF; 

    SELECT reclada.jsonb_merge(v.data, v.default_value) AS data
        FROM reclada.v_active_object v
            WHERE v.obj_id = _obj_id
        INTO _data;
    PERFORM reclada_notification.send_object_notification('update', _data);
    RETURN _data;
END;
$$;


--
-- Name: update_json(jsonb, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.update_json(lobj jsonb, robj jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
    DECLARE
        res     jsonb;
        ltype    text;
        rtype    text;
    BEGIN
        ltype := jsonb_typeof(lobj);
        rtype := jsonb_typeof(robj);
        IF (robj IS NULL) THEN
            RETURN lobj;
        END IF;
        IF (lobj IS NULL) THEN
            RETURN robj;
        END IF;
        IF reclada_object.is_equal(lobj,robj) THEN
            RETURN lobj;
        END IF;
        IF (ltype = 'array' and rtype != 'array') THEN
            RETURN lobj || robj;
        END IF;
        IF (ltype != rtype) THEN
            RETURN robj;
        END IF;
        CASE ltype 
        WHEN 'object' THEN
            SELECT jsonb_object_agg(key,val)
            FROM (
                SELECT key, reclada_object.update_json(lval,rval) AS val
                FROM (                     -- Using joining operators compatible with update_json or hash join is obligatory
                    SELECT (a.rec).key as key,
                        (a.rec).value AS lval,
                        (b.rec).value AS rval                                        --    with FULL OUTER JOIN. update_json is compatible only with NESTED LOOPS
                    FROM (SELECT jsonb_each(lobj) AS rec) a         --    so I use LEFT JOIN UNION ALL RIGHT JOIN insted of FULL OUTER JOIN.
                    LEFT JOIN
                        (SELECT jsonb_each(robj) AS rec) b
                    ON (a.rec).key = (b.rec).key
                UNION
                    SELECT (a.rec).key as key,
                        (b.rec).value AS lval,
                        (a.rec).value AS rval
                    FROM (SELECT jsonb_each(robj) AS rec) a
                    LEFT JOIN
                        (SELECT jsonb_each(lobj) AS rec) b
                    ON (a.rec).key = (b.rec).key
                ) a
            ) b
                INTO res;
            RETURN res;
        WHEN 'array' THEN
            RETURN robj;
        WHEN 'string' THEN
            RETURN robj;
        WHEN 'number' THEN
            RETURN robj;
        WHEN 'boolean' THEN
            RETURN robj;
        WHEN 'null' THEN
            RETURN 'null'::jsonb;   
        ELSE
            RETURN null;
        END CASE;
    END;
$$;


--
-- Name: update_json_by_guid(uuid, jsonb); Type: FUNCTION; Schema: reclada_object; Owner: -
--

CREATE FUNCTION reclada_object.update_json_by_guid(lobj uuid, robj jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
    SELECT reclada_object.update_json(data, robj)
    FROM reclada.v_active_object
    WHERE obj_id = lobj;
$$;


--
-- Name: create(character varying, uuid, uuid, bigint); Type: FUNCTION; Schema: reclada_revision; Owner: -
--

CREATE FUNCTION reclada_revision."create"(userid character varying, branch uuid, obj uuid, tran_id bigint DEFAULT reclada.get_transaction_id()) RETURNS uuid
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
-- Name: auth_by_token(character varying); Type: FUNCTION; Schema: reclada_user; Owner: -
--

CREATE FUNCTION reclada_user.auth_by_token(token character varying) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT '{}'::jsonb
$$;


--
-- Name: disable_auth(jsonb); Type: FUNCTION; Schema: reclada_user; Owner: -
--

CREATE FUNCTION reclada_user.disable_auth(data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM reclada.auth_setting;
END;
$$;


--
-- Name: is_allowed(jsonb, text, text); Type: FUNCTION; Schema: reclada_user; Owner: -
--

CREATE FUNCTION reclada_user.is_allowed(jsonb, text, text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN TRUE;
END;
$$;


--
-- Name: refresh_jwk(jsonb); Type: FUNCTION; Schema: reclada_user; Owner: -
--

CREATE FUNCTION reclada_user.refresh_jwk(data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_oidc_url VARCHAR;
    new_jwk JSONB;
BEGIN
    SELECT oidc_url INTO current_oidc_url FROM reclada.auth_setting FOR UPDATE;
    new_jwk := reclada_user.get_jwk(current_oidc_url);
    UPDATE reclada.auth_setting SET jwk=new_jwk WHERE oidc_url=current_oidc_url;
END;
$$;


--
-- Name: setup_keycloak(jsonb); Type: FUNCTION; Schema: reclada_user; Owner: -
--

CREATE FUNCTION reclada_user.setup_keycloak(data jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    oidc_url VARCHAR;
    jwk JSONB;
BEGIN
    -- check if allowed?
    oidc_url := format(
        '%s/auth/realms/%s/protocol/openid-connect',
        data->>'baseUrl', data->>'realm'
    );
    jwk := reclada_user.get_jwk(oidc_url);

    DELETE FROM reclada.auth_setting;
    INSERT INTO reclada.auth_setting
        (oidc_url, oidc_client_id, oidc_redirect_url, jwk)
    VALUES
        (oidc_url, data->>'clientId', data->>'redirectUrl', jwk);
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


--
-- Name: ##; Type: OPERATOR; Schema: reclada; Owner: -
--

CREATE OPERATOR reclada.## (
    FUNCTION = reclada.xor,
    LEFTARG = boolean,
    RIGHTARG = boolean
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
-- Name: auth_setting; Type: TABLE; Schema: reclada; Owner: -
--

CREATE TABLE reclada.auth_setting (
    oidc_url character varying,
    oidc_client_id character varying,
    oidc_redirect_url character varying,
    jwk jsonb
);


--
-- Name: draft; Type: TABLE; Schema: reclada; Owner: -
--

CREATE TABLE reclada.draft (
    id bigint NOT NULL,
    guid uuid NOT NULL,
    user_guid uuid DEFAULT reclada_object.get_default_user_obj_id(),
    data jsonb NOT NULL,
    parent_guid uuid
);


--
-- Name: draft_id_seq; Type: SEQUENCE; Schema: reclada; Owner: -
--

ALTER TABLE reclada.draft ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME reclada.draft_id_seq
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
-- Name: staging; Type: TABLE; Schema: reclada; Owner: -
--

CREATE TABLE reclada.staging (
    data jsonb NOT NULL
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
-- Name: v_db_trigger_function; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_db_trigger_function AS
 SELECT vo.obj_id AS function_guid,
    (vo.data #>> '{attributes,name}'::text[]) AS function_name
   FROM reclada.v_active_object vo
  WHERE (vo.class_name = 'DBTriggerFunction'::text);


--
-- Name: v_default_display; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_default_display AS
 SELECT 'string'::text AS json_type,
    '{"caption": "#@#attrname#@#","width": 250,"displayCSS": "#@#attrname#@#"}'::text AS template
UNION
 SELECT 'number'::text AS json_type,
    '{"caption": "#@#attrname#@#","width": 250,"displayCSS": "#@#attrname#@#"}'::text AS template
UNION
 SELECT 'boolean'::text AS json_type,
    '{"caption": "#@#attrname#@#","width": 250,"displayCSS": "#@#attrname#@#"}'::text AS template
UNION
 SELECT 'ObjectDisplay'::text AS json_type,
    '{
                        "classGUID": null,
                        "caption": "#@#classname#@#",
                        "table": {
                            "{status}:string":{
                                "caption": "Status",
                                "width": 250,
                                "displayCSS": "status"
                            },
                            "{createdTime}:string":{
                                "caption": "Created time",
                                "width": 250,
                                "displayCSS": "createdTime"
                            },
                            "{transactionID}:number":{
                                "caption": "Transaction",
                                "width": 250,
                                "displayCSS": "transactionID"
                            },
                            "{GUID}:string":{
                                "caption": "GUID",
                                "width": 250,
                                "displayCSS": "GUID"
                            },
                            "orderRow": [
                                {"{transactionID}:number":"DESC"}
                            ],
                            "orderColumn": []
                        },
                        "card":{
                            "{status}:string":{
                                "caption": "Status",
                                "width": 250,
                                "displayCSS": "status"
                            },
                            "{createdTime}:string":{
                                "caption": "Created time",
                                "width": 250,
                                "displayCSS": "createdTime"
                            },
                            "{transactionID}:number":{
                                "caption": "Transaction",
                                "width": 250,
                                "displayCSS": "transactionID"
                            },
                            "{GUID}:string":{
                                "caption": "GUID",
                                "width": 250,
                                "displayCSS": "GUID"
                            },
                            "orderRow": [
                                {"{transactionID}:number":"DESC"}
                            ],
                            "orderColumn": []
                        },
                        "preview":{
                            "{status}:string":{
                                "caption": "Status",
                                "width": 250,
                                "displayCSS": "status"
                            },
                            "{createdTime}:string":{
                                "caption": "Created time",
                                "width": 250,
                                "displayCSS": "createdTime"
                            },
                            "{transactionID}:number":{
                                "caption": "Transaction",
                                "width": 250,
                                "displayCSS": "transactionID"
                            },
                            "{GUID}:string":{
                                "caption": "GUID",
                                "width": 250,
                                "displayCSS": "GUID"
                            },
                            "orderRow": [
                                {"{transactionID}:number":"DESC"}
                            ],
                            "orderColumn": []
                        },
                        "list":{
                            "{status}:string":{
                                "caption": "Status",
                                "width": 250,
                                "displayCSS": "status"
                            },
                            "{createdTime}:string":{
                                "caption": "Created time",
                                "width": 250,
                                "displayCSS": "createdTime"
                            },
                            "{transactionID}:number":{
                                "caption": "Transaction",
                                "width": 250,
                                "displayCSS": "transactionID"
                            },
                            "{GUID}:string":{
                                "caption": "GUID",
                                "width": 250,
                                "displayCSS": "GUID"
                            },
                            "orderRow": [
                                {"{transactionID}:number":"DESC"}
                            ],
                            "orderColumn": []
                        }
                        
                    }'::text AS template;


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
-- Name: v_filter_available_operator; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_filter_available_operator AS
 SELECT ' = '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' LIKE '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' NOT LIKE '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' || '::text AS operator,
    'TEXT'::text AS input_type,
    'TEXT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' ~ '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' !~ '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' ~* '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' !~* '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' SIMILAR TO '::text AS operator,
    'TEXT'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' > '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' < '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' <= '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' != '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' >= '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' AND '::text AS operator,
    'BOOL'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' OR '::text AS operator,
    'BOOL'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' NOT '::text AS operator,
    'BOOL'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' XOR '::text AS operator,
    'BOOL'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' OPERATOR(reclada.##) '::text AS operator,
    'BOOL'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' IS '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' IS NOT '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' IN '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    ' , '::text AS inner_operator
UNION
 SELECT ' @> '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' <@ '::text AS operator,
    'JSONB'::text AS input_type,
    'BOOL'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' + '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' - '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' * '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' / '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' % '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' ^ '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' |/ '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' ||/ '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' !! '::text AS operator,
    'INT'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' @ '::text AS operator,
    'NUMERIC'::text AS input_type,
    'NUMERIC'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' & '::text AS operator,
    'INT'::text AS input_type,
    'INT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' | '::text AS operator,
    'INT'::text AS input_type,
    'INT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' # '::text AS operator,
    'INT'::text AS input_type,
    'INT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' << '::text AS operator,
    'INT'::text AS input_type,
    'INT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' >> '::text AS operator,
    'INT'::text AS input_type,
    'INT'::text AS output_type,
    NULL::text AS inner_operator
UNION
 SELECT ' BETWEEN '::text AS operator,
    'TIMESTAMP WITH TIME ZONE'::text AS input_type,
    'BOOL'::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' Y/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' MON/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' D/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' H/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' MIN/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' S/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' DOW/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' DOY/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' Q/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator
UNION
 SELECT ' W/BETWEEN '::text AS operator,
    NULL::text AS input_type,
    NULL::text AS output_type,
    ' AND '::text AS inner_operator;


--
-- Name: v_filter_between; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_filter_between AS
 SELECT ' Y/BETWEEN '::text AS operator,
    'date_part(''YEAR''   , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' MON/BETWEEN '::text AS operator,
    'date_part(''MONTH''  , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' D/BETWEEN '::text AS operator,
    'date_part(''DAY''    , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' H/BETWEEN '::text AS operator,
    'date_part(''HOUR''   , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' MIN/BETWEEN '::text AS operator,
    'date_part(''MINUTE'' , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' S/BETWEEN '::text AS operator,
    'date_part(''SECOND'' , TIMESTAMP WITH TIME ZONE %s)::int'::text AS operand_format
UNION
 SELECT ' DOW/BETWEEN '::text AS operator,
    'date_part(''DOW''    , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' DOY/BETWEEN '::text AS operator,
    'date_part(''DOY''    , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' Q/BETWEEN '::text AS operator,
    'date_part(''QUARTER'', TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format
UNION
 SELECT ' W/BETWEEN '::text AS operator,
    'date_part(''WEEK''   , TIMESTAMP WITH TIME ZONE %s)'::text AS operand_format;


--
-- Name: v_filter_inner_operator; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_filter_inner_operator AS
 SELECT ' , '::text AS operator,
    'JSONB'::text AS input_type,
    true AS brackets
UNION
 SELECT ' AND '::text AS operator,
    'TIMESTAMP WITH TIME ZONE'::text AS input_type,
    false AS brackets;


--
-- Name: v_filter_mapping; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_filter_mapping AS
 SELECT '{class}'::text AS pattern,
    'class_name'::text AS repl
UNION
 SELECT '{status}'::text AS pattern,
    'status_caption'::text AS repl
UNION
 SELECT '{GUID}'::text AS pattern,
    'obj_id'::text AS repl
UNION
 SELECT '{transactionID}'::text AS pattern,
    'transaction_id'::text AS repl
UNION
 SELECT '{createdTime}'::text AS pattern,
    'created_time'::text AS repl
UNION
 SELECT '{createdBy}'::text AS pattern,
    'created_by'::text AS repl
UNION
 SELECT '{classGUID}'::text AS pattern,
    'class'::text AS repl
UNION
 SELECT '{parentGUID}'::text AS pattern,
    'parent_guid'::text AS repl;


--
-- Name: v_get_duplicates_query; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_get_duplicates_query AS
 SELECT 'SELECT ''
    SELECT vao.obj_id, 
            '''''' || dup_behavior || ''''''::reclada.dp_bhvr,
            '' || is_cascade || '',
            '''''' || COALESCE (copy_field,'''') ||'''''' FROM reclada.v_active_object vao WHERE '' ||  string_agg(predicate, '' OR '') @#@#@exclude_uuid@#@#@
          FROM (SELECT string_agg(''(vao.attrs ->>'''''' || unifield || '''''')'', ''||'' ORDER BY field_number) || ''='''''' || string_agg(COALESCE((''@#@#@attrs@#@#@''::jsonb) ->> unifield,''''),''''  ORDER BY field_number) || '''''''' AS predicate,
          dup_behavior , is_cascade , copy_field
          FROM reclada.v_object_unifields vou 
          WHERE class_uuid = ''@#@#@class_uuid@#@#@''
            AND is_mandatory
          GROUP BY uni_number, dup_behavior , is_cascade , copy_field) a
         GROUP BY dup_behavior , is_cascade , copy_field
'::text AS val;


--
-- Name: v_import_info; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_import_info AS
 SELECT obj.id,
    obj.obj_id AS guid,
    ((obj.attrs ->> 'tranID'::text))::bigint AS tran_id,
    (obj.attrs ->> 'name'::text) AS name,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'ImportInfo'::text);


--
-- Name: v_object_display; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_object_display AS
 SELECT obj.id,
    obj.guid,
    ((obj.attributes ->> 'classGUID'::text))::uuid AS class_guid,
    (obj.attributes ->> 'caption'::text) AS caption,
    (obj.attributes -> 'table'::text) AS "table",
    (obj.attributes -> 'card'::text) AS card,
    (obj.attributes -> 'preview'::text) AS preview,
    (obj.attributes -> 'list'::text) AS list,
    obj.created_time,
    obj.attributes,
    obj.status
   FROM reclada.object obj
  WHERE ((obj.class IN ( SELECT reclada_object.get_guid_for_class('ObjectDisplay'::text) AS get_guid_for_class)) AND (obj.status = reclada_object.get_active_status_obj_id()));


--
-- Name: v_object_unifields; Type: MATERIALIZED VIEW; Schema: reclada; Owner: -
--

CREATE MATERIALIZED VIEW reclada.v_object_unifields AS
 SELECT b.for_class,
    b.class_uuid,
    (b.dup_behavior)::reclada.dp_bhvr AS dup_behavior,
    b.is_cascade,
    b.is_mandatory,
    b.uf AS unifield,
    b.uni_number,
    row_number() OVER (PARTITION BY b.for_class, b.uni_number ORDER BY b.uf) AS field_number,
    b.copy_field
   FROM ( SELECT a.for_class,
            a.obj_id AS class_uuid,
            a.dup_behavior,
            (a.is_cascade)::boolean AS is_cascade,
            ((a.dc ->> 'isMandatory'::text))::boolean AS is_mandatory,
            jsonb_array_elements_text((a.dc -> 'uniFields'::text)) AS uf,
            (a.dc -> 'uniFields'::text) AS field_list,
            row_number() OVER (PARTITION BY a.for_class ORDER BY (a.dc -> 'uniFields'::text)) AS uni_number,
            a.copy_field
           FROM ( SELECT vc.for_class,
                    (vc.attributes ->> 'dupBehavior'::text) AS dup_behavior,
                    (vc.attributes ->> 'isCascade'::text) AS is_cascade,
                    jsonb_array_elements((vc.attributes -> 'dupChecking'::text)) AS dc,
                    vc.obj_id,
                    (vc.attributes ->> 'copyField'::text) AS copy_field
                   FROM reclada.v_class_lite vc
                  WHERE (((vc.attributes -> 'dupChecking'::text) IS NOT NULL) AND (vc.status = reclada_object.get_active_status_obj_id()))) a) b
  WITH NO DATA;


--
-- Name: v_parent_field; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_parent_field AS
 SELECT v_class.for_class,
    v_class.obj_id AS class_uuid,
    (v_class.attributes ->> 'parentField'::text) AS parent_field
   FROM reclada.v_class_lite v_class
  WHERE ((v_class.attributes ->> 'parentField'::text) IS NOT NULL);


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
-- Name: v_task; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_task AS
 SELECT obj.id,
    obj.obj_id AS guid,
    (obj.attrs ->> 'type'::text) AS type,
    (obj.attrs ->> 'command'::text) AS command,
    obj.revision_num,
    obj.status_caption,
    obj.revision,
    obj.created_time,
    obj.attrs,
    obj.status,
    obj.data
   FROM reclada.v_active_object obj
  WHERE (obj.class_name = 'Task'::text);


--
-- Name: v_trigger; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_trigger AS
 SELECT vo.obj_id AS trigger_guid,
    ((vo.data #>> '{attributes,function}'::text[]))::uuid AS function_guid,
    (vo.data #>> '{attributes,action}'::text[]) AS trigger_type,
    (vo.data #> '{attributes,forClasses}'::text[]) AS for_classes
   FROM reclada.v_active_object vo
  WHERE (vo.class_name = 'DBTrigger'::text);


--
-- Name: v_ui_active_object; Type: VIEW; Schema: reclada; Owner: -
--

CREATE VIEW reclada.v_ui_active_object AS
 SELECT 'with recursive 
d as ( 
    SELECT  reclada.jsonb_merge(obj.data, obj.default_value) AS data,
            obj_id,
            created_time,
            attrs
        FROM reclada.v_active_object obj 
            where #@#@#where#@#@#
                ORDER BY #@#@#orderby#@#@#
                OFFSET #@#@#offset#@#@#
                LIMIT #@#@#limit#@#@#
),
t as
(
    SELECT  je.key,
            1 as q,
            jsonb_typeof(je.value) typ,
            d.obj_id,
            je.value
        from d 
        JOIN LATERAL jsonb_each(d.data) je
            on true
        -- where jsonb_typeof(je.value) != ''null''
    union
    SELECT 
            d.key ||'',''|| je.key as key ,
            d.q,
            jsonb_typeof(je.value) typ,
            d.obj_id,
            je.value
        from (
            select  d.data #> (''{''||t.key||''}'')::text[] as data, 
                    t.q+1 as q,
                    t.key,
                    d.obj_id
            from t 
            join d
                on t.typ = ''object''
        ) d
        JOIN LATERAL jsonb_each(d.data) je
            on true
        -- where jsonb_typeof(je.value) != ''null''
),
res as
(
    select  rr.obj_id,
            rr.data,
            rr.display_key,
            o.attrs,
            o.created_time,
            o.id
        from
        (
            select  t.obj_id,
                    jsonb_object_agg
                    (
                        ''{''||t.key||''}'',
                        t.value
                    ) as data,
                    array_agg(
                        t.key||''#@#@#separator#@#@#''||t.typ 
                    ) as display_key
                from t 
                    where t.typ != ''object''
                    group by t.obj_id
        ) rr
        join reclada.v_active_object o
            on o.obj_id = rr.obj_id
)
'::text AS val;


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
2	2	\N	begin;\nSET CLIENT_ENCODING TO 'utf8';\nCREATE TEMP TABLE var_table\n    (\n        ver int,\n        upgrade_script text,\n        downgrade_script text\n    );\n    \ninsert into var_table(ver)\t\n    select max(ver) + 1\n        from dev.VER;\n        \nselect reclada.raise_exception('Can not apply this version!') \n    where not exists\n    (\n        select ver from var_table where ver = 2 --!!! write current version HERE !!!\n    );\n\nCREATE TEMP TABLE tmp\n(\n    id int GENERATED ALWAYS AS IDENTITY,\n    str text\n);\n--{ logging upgrade script\nCOPY tmp(str) FROM  'up.sql' delimiter E'';\nupdate var_table set upgrade_script = array_to_string(ARRAY((select str from tmp order by id asc)),chr(10),'');\ndelete from tmp;\n--} logging upgrade script\t\n\n--{ create downgrade script\nCOPY tmp(str) FROM  'down.sql' delimiter E'';\nupdate tmp set str = drp.v || scr.v\n    from tmp ttt\n    inner JOIN LATERAL\n    (\n        select substring(ttt.str from 4 for length(ttt.str)-4) as v\n    )  obj_file_name ON TRUE\n    inner JOIN LATERAL\n    (\n        select \tsplit_part(obj_file_name.v,'/',1) typ,\n                split_part(obj_file_name.v,'/',2) nam\n    )  obj ON TRUE\n        inner JOIN LATERAL\n    (\n        select case\n                when obj.typ = 'trigger'\n                    then\n                        (select 'DROP '|| obj.typ || ' IF EXISTS '|| obj.nam ||' ON ' || schm||'.'||tbl ||';' || E'\n'\n                        from (\n                            select n.nspname as schm,\n                                   c.relname as tbl\n                            from pg_trigger t\n                                join pg_class c on c.oid = t.tgrelid\n                                join pg_namespace n on n.oid = c.relnamespace\n                            where t.tgname = obj.nam) o)\n                else 'DROP '||obj.typ|| ' IF EXISTS '|| obj.nam || ' ;' || E'\n'\n                end as v\n    )  drp ON TRUE\n    inner JOIN LATERAL\n    (\n        select case \n                when obj.typ in ('function', 'procedure')\n                    then\n                        case \n                            when EXISTS\n                                (\n                                    SELECT 1 a\n                                        FROM pg_proc p \n                                        join pg_namespace n \n                                            on p.pronamespace = n.oid \n                                            where n.nspname||'.'||p.proname = obj.nam\n                                        LIMIT 1\n                                ) \n                                then (select pg_catalog.pg_get_functiondef(obj.nam::regproc::oid))||';'\n                            else ''\n                        end\n                when obj.typ = 'view'\n                    then\n                        case \n                            when EXISTS\n                                (\n                                    select 1 a \n                                        from pg_views v \n                                            where v.schemaname||'.'||v.viewname = obj.nam\n                                        LIMIT 1\n                                ) \n                                then E'CREATE OR REPLACE VIEW '\n                                        || obj.nam\n                                        || E'\nAS\n'\n                                        || (select pg_get_viewdef(obj.nam, true))\n                            else ''\n                        end\n                when obj.typ = 'trigger'\n                    then\n                        case\n                            when EXISTS\n                                (\n                                    select 1 a\n                                        from pg_trigger v\n                                            where v.tgname = obj.nam\n                                        LIMIT 1\n                                )\n                                then (select pg_catalog.pg_get_triggerdef(oid, true)\n                                        from pg_trigger\n                                        where tgname = obj.nam)||';'\n                            else ''\n                        end\n                else \n                    ttt.str\n            end as v\n    )  scr ON TRUE\n    where ttt.id = tmp.id\n        and tmp.str like '--{%/%}';\n    \nupdate var_table set downgrade_script = array_to_string(ARRAY((select str from tmp order by id asc)),chr(10),'');\t\n--} create downgrade script\ndrop table tmp;\n\n\n--{!!! write upgrare script HERE !!!\n\n--\tyou can use "i 'function/reclada_object.get_schema.sql'"\n--\tto run text script of functions\n \n/*\n    you can use "i 'function/reclada_object.get_schema.sql'"\n    to run text script of functions\n*/\n\ncreate table public.test (id int, val text);\n\n SELECT reclada.raise_notice('Begin install component db...');\n                SELECT dev.begin_install_component('db','https://github.com/Unrealman17/db_ver','3b642092541812549301b9b3f6b42d2a7401c50b');\n                \n-- 1\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "tag",\n        "properties": {\n            "name": {"type": "string"}\n        },\n        "required": ["name"]\n    }\n}'::jsonb);\n-- 2\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "DataSource",\n        "properties": {\n            "name": {"type": "string"},\n            "uri": {"type": "string"}\n        },\n        "required": ["name"]\n    }\n}'::jsonb);\n-- 3\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "S3Config",\n        "properties": {\n            "endpointURL": {"type": "string"},\n            "regionName": {"type": "string"},\n            "accessKeyId": {"type": "string"},\n            "secretAccessKey": {"type": "string"},\n            "bucketName": {"type": "string"}\n            },\n        "required": ["accessKeyId", "secretAccessKey", "bucketName"]\n    }\n}'::jsonb);\n--{ 4 DataSet\nSELECT reclada_object.create_subclass('{\n        "class": "RecladaObject",\n        "attributes": {\n            "newClass": "DataSet",\n            "properties": {\n                "name": {"type": "string"},\n                "dataSources": {\n                    "type": "array",\n                    "items": {"type": "string"}\n                }\n            },\n            "required": ["name"]\n        }\n    }'::jsonb);\n\n        SELECT reclada_object.create('{\n            "GUID":"10c400ff-a328-450d-ae07-ce7d427d961c",\n            "class": "DataSet",\n            "attributes": {\n                "name": "defaultDataSet",\n                "dataSources": []\n            }\n        }'::jsonb);\n--} 4 DataSet\n\n-- 5\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "Message",\n        "properties": {\n            "channelName": {"type": "string"},\n            "class": {"type": "string"},\n            "event": {\n                "type": "string",\n                "enum": [\n                    "create",\n                    "update",\n                    "list",\n                    "delete"\n                ]\n            },\n            "attributes": {\n                "type": "array", \n                "items": {"type": "string"}\n            }\n        },\n        "required": ["class", "channelName", "event"]\n    }\n}'::jsonb);\n\n--{ 6 Index\nSELECT reclada_object.create_subclass('{\n            "class": "RecladaObject",\n            "attributes": {\n                "newClass": "Index",\n                "properties": {\n                    "name": {"type": "string"},\n                    "method": {\n                        "type": "string",\n                        "enum ": [\n                            "btree", \n                            "hash" , \n                            "gist" , \n                            "gin"\n                        ]\n                    },\n                    "wherePredicate": {\n                        "type": "string"\n                    },\n                    "fields": {\n                        "items": {\n                            "type": "string"\n                        },\n                        "type": "array",\n                        "minContains": 1\n                    }\n                },\n                "required": ["name","fields"]\n            }\n        }'::jsonb);\n\n    select reclada_object.create('{\n            "GUID": "db0873d1-786f-4d5d-b790-5c3b3cd29baf",\n            "class": "Index",\n            "attributes": {\n                "name": "checksum_index_",\n                "fields": ["(attributes ->> ''checksum''::text)"],\n                "method": "hash",\n                "wherePredicate": "((attributes ->> ''checksum''::text) IS NOT NULL)"\n            }\n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db08d53b-c423-4e94-8b14-e73ebe98e991",\n            "class": "Index",\n            "attributes": {\n                "name": "repository_index_",\n                "fields": ["(attributes ->> ''repository''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''repository''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n        "GUID": "db05e253-7954-4610-b094-8f9925ea77b4",\n        "class": "Index",\n        "attributes": {\n                "name": "commithash_index_",\n                "fields": ["(attributes ->> ''commitHash''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''commitHash''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n        "GUID": "db02f980-cd5a-4c1a-9341-7a81713cd9d0",\n        "class": "Index",\n        "attributes": {\n                "name": "fields_index_",\n                "fields": ["(attributes ->> ''fields''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''fields''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0e400b-1da4-4823-bb80-15eb144a1639",\n            "class": "Index",\n            "attributes": {\n                    "name": "caption_index_",\n                    "fields": ["(attributes ->> ''caption''::text)"],\n                    "method": "btree",\n                    "wherePredicate": "((attributes ->> ''caption''::text) IS NOT NULL)"\n                }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db09fafb-91b1-4fe6-8e5c-1cd2d7d9225a",\n            "class": "Index",\n            "attributes": {\n                "name": "type_index",\n                "fields": ["(attributes ->> ''type''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''type''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0118e5-ea34-45dc-b72c-f16f6a628ddb",\n            "class": "Index",\n            "attributes": {\n                "name": "schema_index_",\n                "fields": ["(attributes ->> ''schema''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''schema''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db07c919-5bc0-4fec-961c-f558401d3e71",\n            "class": "Index",\n            "attributes": {\n                "name": "forclass_index_",\n                "fields": ["(attributes ->> ''forclass''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''forclass''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0184b8-556e-4f57-af12-d84066adbe31",\n            "class": "Index",\n            "attributes": {\n                "name": "revision_index",\n                "fields": ["(attributes ->> ''revision''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''revision''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0e22c0-e0d7-4b11-bf25-367a8fbdef83",\n            "class": "Index",\n            "attributes": {\n                "name": "subject_index_",\n                "fields": ["(attributes ->> ''subject''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''subject''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db05c9c7-17ce-4b36-89d7-81b0ddd26a6a",\n            "class": "Index",\n            "attributes": {\n                "name": "class_index_",\n                "fields": ["(attributes ->> ''class''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''class''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0a88c1-ac00-42e5-9caa-6007a1c948c6",\n            "class": "Index",\n                "attributes": {\n                "name": "name_index_",\n                "fields": ["(attributes ->> ''name''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''name''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0fdc46-6479-4d20-bd21-a6330905e45b",\n            "class": "Index",\n            "attributes": {\n                "name": "event_index_",\n                "fields": ["(attributes ->> ''event''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''event''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db02b45a-acfd-4448-a51a-8e7dc35bf3af",\n            "class": "Index",\n            "attributes": {\n                "name": "function_index_",\n                "fields": ["(attributes ->> ''function''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''function''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db0b797a-b287-4282-b0f8-d985c7a439f4",\n            "class": "Index",\n            "attributes": {\n                "name": "login_index_",\n                "fields": ["(attributes ->> ''login''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''login''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n    select reclada_object.create('{\n            "GUID": "db03c715-c0f9-43c3-940a-803aafa513e0",\n            "class": "Index",\n            "attributes": {\n                "name": "object_index_",\n                "fields": ["(attributes ->> ''object''::text)"],\n                "method": "btree",\n                "wherePredicate": "((attributes ->> ''object''::text) IS NOT NULL)"\n            }    \n        }'::jsonb);\n\n--} 6 Index\n\n-- 7\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "Component",\n        "properties": {\n            "name": {"type": "string"},\n            "commitHash": {"type": "string"},\n            "repository": {"type": "string"}\n        },\n        "required": ["name","commitHash","repository"]\n    }\n}'::jsonb);\n\n--{ 9 DTOJsonSchema\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "DTOJsonSchema",\n        "properties": {\n            "schema": {"type": "object"},\n            "function": {"type": "string"}\n        },\n        "required": ["schema","function"]\n    }\n}'::jsonb);\n\n    SELECT reclada_object.create('{\n            "GUID":"db0bf6f5-7eea-4dbd-9f46-e0535f7fb299",\n            "class": "DTOJsonSchema",\n            "attributes": {\n                "function": "reclada_object.get_query_condition_filter",\n                "schema": {\n                    "id": "expr",\n                    "type": "object",\n                    "required": [\n                        "value",\n                        "operator"\n                    ],\n                    "properties": {\n                        "value": {\n                            "type": "array",\n                            "items": {\n                                "anyOf": [\n                                    {\n                                        "type": "string"\n                                    },\n                                    {\n                                        "type": "null"\n                                    },\n                                    {\n                                        "type": "number"\n                                    },\n                                    {\n                                        "$ref": "expr"\n                                    },\n                                    {\n                                        "type": "boolean"\n                                    },\n                                    {\n                                        "type": "array",\n                                        "items": {\n                                            "anyOf": [\n                                                {\n                                                    "type": "string"\n                                                },\n                                                {\n                                                    "type": "number"\n                                                }\n                                            ]\n                                        }\n                                    }\n                                ]\n                            },\n                            "minItems": 1\n                        },\n                        "operator": {\n                            "type": "string"\n                        }\n                    }\n                }\n            }\n        }'::jsonb);\n\n     SELECT reclada_object.create('{\n            "GUID":"db0ad26e-a522-4907-a41a-a82a916fdcf9",\n            "class": "DTOJsonSchema",\n            "attributes": {\n                "function": "reclada_object.list",\n                "schema": {\n                    "type": "object",\n                    "anyOf": [\n                        {\n                            "required": [\n                                "transactionID"\n                            ]\n                        },\n                        {\n                            "required": [\n                                "class"\n                            ]\n                        },\n                        {\n                            "required": [\n                                "filter"\n                            ]\n                        }\n                    ],\n                    "properties": {\n                        "class": {\n                            "type": "string"\n                        },\n                        "limit": {\n                            "anyOf": [\n                                {\n                                    "enum": [\n                                        "ALL"\n                                    ],\n                                    "type": "string"\n                                },\n                                {\n                                    "type": "integer"\n                                }\n                            ]\n                        },\n                        "filter": {\n                            "type": "object"\n                        },\n                        "offset": {\n                            "type": "integer"\n                        },\n                        "orderBy": {\n                            "type": "array",\n                            "items": {\n                                "type": "object",\n                                "required": [\n                                    "field"\n                                ],\n                                "properties": {\n                                    "field": {\n                                        "type": "string"\n                                    },\n                                    "order": {\n                                        "enum": [\n                                            "ASC",\n                                            "DESC"\n                                        ],\n                                        "type": "string"\n                                    }\n                                }\n                            }\n                        },\n                        "transactionID": {\n                            "type": "integer"\n                        }\n                    }\n                }\n            }\n            \n        }'::jsonb);\n--} 9 DTOJsonSchema\n\n-- 10\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n\n        "dupBehavior": "Replace",\n        "dupChecking": [\n            {\n                "isMandatory": true,\n                "uniFields": [\n                    "uri"\n                ]\n            },\n            {\n                "isMandatory": true,\n                "uniFields": [\n                    "checksum"\n                ]\n            }\n        ],\n        "isCascade": true,\n\n        "newClass": "File",\n        "properties": {\n            "uri": {"type": "string"},\n            "name": {"type": "string"},\n            "mimeType": {"type": "string"},\n            "checksum": {"type": "string"}\n        },\n        "required": ["uri","mimeType","name"]\n    }\n}'::jsonb);\n\n--{ 11 User\nSELECT reclada_object.create_subclass('{\n    "GUID":"db0db7c0-9b25-4af0-8013-d2d98460cfff",\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "User",\n        "properties": {\n            "login": {"type": "string"}\n        },\n        "required": ["login"]\n    }\n}'::jsonb);\n\n    select reclada_object.create('{\n            "GUID": "db0789c1-1b4e-4815-b70c-4ef060e90884",\n            "class": "User",\n            "attributes": {\n                "login": "dev"\n            }\n        }'::jsonb);\n--} 11 User\n\n-- 12\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "ImportInfo",\n        "properties": {\n            "tranID": {"type": "number"},\n            "name": {"type": "string"}\n        },\n        "required": ["tranID","name"]\n    }\n}'::jsonb);\n-- 13\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "Asset",\n        "properties": {\n            "name": {"type": "string"},\n            "uri": {"type": "string"}\n        },\n        "required": ["name"]\n    }\n}'::jsonb);\n-- 14\nSELECT reclada_object.create_subclass('{\n    "class": "Asset",\n    "attributes": {\n        "newClass": "DBAsset"\n    }\n}'::jsonb);\n-- 15\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "revision",\n        "properties": {\n            "branch": {"type": "string"},\n            "user": {"type": "string"},\n            "num": {"type": "number"},\n            "dateTime": {"type": "string"}\n        },\n        "required": ["dateTime"]\n    }\n}'::jsonb);\n\n--{ 16 ObjectDisplay\nSELECT reclada_object.create_subclass('{\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "ObjectDisplay",\n        "$defs": {\n            "displayType": {\n                "properties": {\n                    "orderColumn": {\n                        "items": {\n                            "type": "string"\n                        },\n                        "type": "array"\n                    },\n                    "orderRow": {\n                        "items": {\n                            "patternProperties": {\n                                "^{.*}$": {\n                                    "enum": [\n                                        "ASC",\n                                        "DESC"\n                                    ],\n                                    "type": "string"\n                                }\n                            },\n                            "type": "object"\n                        },\n                        "type": "array"\n                    }\n                },\n                "required": [\n                    "orderColumn",\n                    "orderRow"\n                ],\n                "type": "object"\n            }\n        },\n        "properties": {\n            "caption": {\n                "type": "string"\n            },\n            "card": {\n                "$ref": "#/$defs/displayType"\n            },\n            "classGUID": {\n                "type": "string",\n                "pattern": "[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}"\n            },\n            "flat": {\n                "type": "bool"\n            },\n            "list": {\n                "$ref": "#/$defs/displayType"\n            },\n            "preview": {\n                "$ref": "#/$defs/displayType"\n            },\n            "table": {\n                "$ref": "#/$defs/displayType"\n            }\n        },\n        "required": [\n            "classGUID",\n            "caption"\n        ]\n    }\n}'::jsonb);\n\n    SELECT reclada_object.create(('{\n        "GUID": "db09dd42-f2a2-4e34-90ea-a6e5f5ea6dff",\n        "class": "ObjectDisplay",\n        "attributes": {\n            "card": {\n                "orderRow": [\n                    {\n                        "{attributes,name}:string": "ASC"\n                    },\n                    {\n                        "{attributes,mimeType}:string": "DESC"\n                    }\n                ],\n                "orderColumn": [\n                    "{attributes,name}:string",\n                    "{attributes,mimeType}:string",\n                    "{attributes,tags}:array",\n                    "{status}:string",\n                    "{createdTime}:string",\n                    "{transactionID}:number"\n                ]\n            },\n            "list": {\n                "orderRow": [\n                    {\n                        "{attributes,name}:string": "ASC"\n                    },\n                    {\n                        "{attributes,mimeType}:string": "DESC"\n                    }\n                ],\n                "orderColumn": [\n                    "{attributes,name}:string",\n                    "{attributes,mimeType}:string",\n                    "{attributes,tags}:array",\n                    "{status}:string",\n                    "{createdTime}:string",\n                    "{transactionID}:number"\n                ]\n            },\n            "table": {\n                "orderRow": [\n                    {\n                        "{attributes,name}:string": "ASC"\n                    },\n                    {\n                        "{attributes,mimeType}:string": "DESC"\n                    }\n                ],\n                "orderColumn": [\n                    "{attributes,name}:string",\n                    "{attributes,mimeType}:string",\n                    "{attributes,tags}:array",\n                    "{status}:string",\n                    "{createdTime}:string",\n                    "{transactionID}:number"\n                ],\n                "{GUID}:string": {\n                    "width": 250,\n                    "caption": "GUID",\n                    "displayCSS": "GUID"\n                },\n                "{status}:string": {\n                    "width": 250,\n                    "caption": "Status",\n                    "displayCSS": "status"\n                },\n                "{createdTime}:string": {\n                    "width": 250,\n                    "caption": "Created time",\n                    "displayCSS": "createdTime"\n                },\n                "{transactionID}:number": {\n                    "width": 250,\n                    "caption": "Transaction",\n                    "displayCSS": "transactionID"\n                },\n                "{attributes,tags}:array": {\n                    "items": {\n                        "class": "e12e729b-ac44-45bc-8271-9f0c6d4fa27b",\n                        "behavior": "preview",\n                        "displayCSS": "link"\n                    },\n                    "width": 250,\n                    "caption": "Tags",\n                    "displayCSS": "arrayLink"\n                },\n                "{attributes,name}:string": {\n                    "width": 250,\n                    "caption": "File name",\n                    "behavior": "preview",\n                    "displayCSS": "name"\n                },\n                "{attributes,checksum}:string": {\n                    "width": 250,\n                    "caption": "Checksum",\n                    "displayCSS": "checksum"\n                },\n                "{attributes,mimeType}:string": {\n                    "width": 250,\n                    "caption": "Mime type",\n                    "displayCSS": "mimeType"\n                }\n            },\n            "caption": "Files",\n            "preview": {\n                "orderRow": [\n                    {\n                        "{attributes,name}:string": "ASC"\n                    },\n                    {\n                        "{attributes,mimeType}:string": "DESC"\n                    }\n                ],\n                "orderColumn": [\n                    "{attributes,name}:string",\n                    "{attributes,mimeType}:string",\n                    "{attributes,tags}:array",\n                    "{status}:string",\n                    "{createdTime}:string",\n                    "{transactionID}:number"\n                ]\n            },\n            "classGUID": "'|| (SELECT obj_id\n                                FROM reclada.v_class\n                                    WHERE for_class = 'File'\n                                    ORDER BY ID DESC\n                                    LIMIT 1 ) ||'"\n        }\n    }')::jsonb);\n\n--} 16 ObjectDisplay\n\n--{ 17 View\nSELECT reclada_object.create_subclass('{\n        "GUID":"db09dcaa-fc90-4760-af68-f855cbe9c2b0",\n        "class": "RecladaObject",\n        "attributes": {\n            "newClass": "View",\n            "properties": {\n                "name": {"type": "string"},\n                "query": {"type": "string"}\n            },\n            "required": ["name","query"]\n        }\n    }'::jsonb);\n--} 17 View\n\n--{ 18 Function\nSELECT reclada_object.create_subclass('{\n        "GUID":"db0d8ccd-a06e-46c3-9836-a8b4b68f3cd4",\n        "class": "RecladaObject",\n        "attributes": {\n            "newClass": "Function",\n            "$defs": {\n                "declare":{\n                    "type":"array",\n                    "items": {\n                        "type": "object",\n                        "properties":{\n                            "name":{"type": "string"},\n                            "type":{\n                                "type": "string",\n                                "enum": [\n                                    "uuid" ,\n                                    "jsonb",\n                                    "text" ,\n                                    "bigint"\n                                ]\n                            }\n                        },\n                        "required": ["name","type"]\n                    }\n                }\n            },\n            "properties": {\n                "name": {"type": "string"},\n                "parameters": { "$ref": "#/$defs/declare" },\n                "returns": {\n                    "type": "string",\n                    "enum": [\n                        "void",\n                        "uuid" ,\n                        "jsonb",\n                        "text" ,\n                        "bigint"\n                    ]\n                },\n                "declare": { "$ref": "#/$defs/declare" },\n                "body": {"type": "string"}\n            },\n            "required": ["name","returns","body"]\n        }\n    }'::jsonb);\n--} 18 Function\n\n--{ 19 DBTriggerFunction\nSELECT reclada_object.create_subclass('{\n        "GUID":"db0635d4-33be-4b5c-8af4-c90038665b7d",\n        "class": "Function",\n        "attributes": {\n            "newClass": "DBTriggerFunction",\n            "properties": {\n                "parameters": {\n                    "type":"array",\n                    "minItems": 1,\n                    "maxItems": 1,\n                    "items": {\n                        "type": "object",\n                        "properties":{\n                            "name":{\n                                "type": "string", \n                                "enum": ["object_id"]\n                            },\n                            "type":{\n                                "type": "string",\n                                "enum": ["bigint"]\n                            }\n                        },\n                        "required": ["name","type"]\n                    }\n                },\n                "returns": {\n                    "type": "string",\n                    "enum": [\n                        "void"]\n                }\n            },\n            "required": ["parameters"]\n        }\n    }'::jsonb);\n--} 19 DBTriggerFunction\n\n\n--{ 20 Trigger\nSELECT reclada_object.create_subclass('{\n    "GUID":"db05bc71-4f3c-4276-9b97-c9e83f21c813",\n    "class": "RecladaObject",\n    "attributes": {\n        "newClass": "DBTrigger",\n        "properties": {\n            "name": {"type": "string"},\n            "action": {\n                "type": "string",\n                "enum": [\n                    "insert",\n                    "delete"\n                ]\n            },\n            "forClasses": {\n                "type": "array",\n                "items": {"type": "string"}\n            },\n            "function":{\n                "type": "string",\n                "pattern": "[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}"\n            }\n        },\n        "required": ["name","action","forClasses","function"]\n    }\n }'::jsonb);\n--} 20 Trigger\n                SELECT dev.finish_install_component();\n\n--}!!! write upgrare script HERE !!!\n\ninsert into dev.ver(ver,upgrade_script,downgrade_script)\n    select ver, upgrade_script, downgrade_script\n        from var_table;\n\n--{ testing downgrade script\nSAVEPOINT sp;\n    select dev.downgrade_version();\nROLLBACK TO sp;\n--} testing downgrade script\n\nselect reclada.raise_notice('OK, current version: ' \n                            || (select ver from var_table)::text\n                          );\ndrop table var_table;\n\ncommit;	-- you can use "--{function/reclada_object.get_schema}"\n-- to add current version of object to downgrade script\n\ndrop table public.test;	2022-09-05 06:23:15.362104+00
\.


--
-- Data for Name: auth_setting; Type: TABLE DATA; Schema: reclada; Owner: -
--

COPY reclada.auth_setting (oidc_url, oidc_client_id, oidc_redirect_url, jwk) FROM stdin;
\.


--
-- Data for Name: draft; Type: TABLE DATA; Schema: reclada; Owner: -
--

COPY reclada.draft (id, guid, user_guid, data, parent_guid) FROM stdin;
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
-- Data for Name: staging; Type: TABLE DATA; Schema: reclada; Owner: -
--

COPY reclada.staging (data) FROM stdin;
\.


--
-- Name: component_object_id_seq; Type: SEQUENCE SET; Schema: dev; Owner: -
--

SELECT pg_catalog.setval('dev.component_object_id_seq', 549, true);


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

SELECT pg_catalog.setval('dev.ver_id_seq', 2, true);


--
-- Name: draft_id_seq; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.draft_id_seq', 1, false);


--
-- Name: object_id_seq; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.object_id_seq', 1072, true);


--
-- Name: transaction_id; Type: SEQUENCE SET; Schema: reclada; Owner: -
--

SELECT pg_catalog.setval('reclada.transaction_id', 587, true);


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
-- Name: colspan_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX colspan_index_v47 ON reclada.object USING btree (((attributes -> 'colspan'::text))) WHERE ((attributes -> 'colspan'::text) IS NOT NULL);


--
-- Name: column_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX column_index_v47 ON reclada.object USING btree (((attributes -> 'column'::text))) WHERE ((attributes -> 'column'::text) IS NOT NULL);


--
-- Name: environment_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX environment_index_v47 ON reclada.object USING hash (((attributes -> 'environment'::text))) WHERE ((attributes -> 'environment'::text) IS NOT NULL);


--
-- Name: event_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX event_index_v47 ON reclada.object USING hash (((attributes -> 'event'::text))) WHERE ((attributes -> 'event'::text) IS NOT NULL);


--
-- Name: guid_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX guid_index ON reclada.object USING hash (guid);


--
-- Name: height_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX height_index_v47 ON reclada.object USING btree (((attributes -> 'height'::text))) WHERE ((attributes -> 'height'::text) IS NOT NULL);


--
-- Name: left_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX left_index_v47 ON reclada.object USING btree (((attributes -> 'left'::text))) WHERE ((attributes -> 'left'::text) IS NOT NULL);


--
-- Name: nexttask_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX nexttask_index_v47 ON reclada.object USING hash (((attributes -> 'nexttask'::text))) WHERE ((attributes -> 'nexttask'::text) IS NOT NULL);


--
-- Name: number_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX number_index_v47 ON reclada.object USING btree (((attributes -> 'number'::text))) WHERE ((attributes -> 'number'::text) IS NOT NULL);


--
-- Name: object_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX object_index_v47 ON reclada.object USING hash (((attributes -> 'object'::text))) WHERE ((attributes -> 'object'::text) IS NOT NULL);


--
-- Name: parent_guid_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX parent_guid_index ON reclada.object USING hash (parent_guid) WHERE (parent_guid IS NOT NULL);


--
-- Name: relationship_type_subject_object_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX relationship_type_subject_object_index ON reclada.object USING btree (((attributes ->> 'type'::text)), (((attributes ->> 'subject'::text))::uuid), status, (((attributes ->> 'object'::text))::uuid)) WHERE (((attributes ->> 'subject'::text) IS NOT NULL) AND ((attributes ->> 'object'::text) IS NOT NULL));


--
-- Name: row_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX row_index_v47 ON reclada.object USING btree (((attributes -> 'row'::text))) WHERE ((attributes -> 'row'::text) IS NOT NULL);


--
-- Name: rowspan_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX rowspan_index_v47 ON reclada.object USING btree (((attributes -> 'rowspan'::text))) WHERE ((attributes -> 'rowspan'::text) IS NOT NULL);


--
-- Name: runner_type_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX runner_type_index ON reclada.object USING btree (((attributes ->> 'type'::text))) WHERE ((attributes ->> 'type'::text) IS NOT NULL);


--
-- Name: subject_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX subject_index_v47 ON reclada.object USING hash (((attributes -> 'subject'::text))) WHERE ((attributes -> 'subject'::text) IS NOT NULL);


--
-- Name: task_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX task_index_v47 ON reclada.object USING hash (((attributes -> 'task'::text))) WHERE ((attributes -> 'task'::text) IS NOT NULL);


--
-- Name: tasks_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX tasks_index_v47 ON reclada.object USING gin (((attributes -> 'tasks'::text))) WHERE ((attributes -> 'tasks'::text) IS NOT NULL);


--
-- Name: top_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX top_index_v47 ON reclada.object USING btree (((attributes -> 'top'::text))) WHERE ((attributes -> 'top'::text) IS NOT NULL);


--
-- Name: tranid_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX tranid_index_v47 ON reclada.object USING btree (((attributes -> 'tranid'::text))) WHERE ((attributes -> 'tranid'::text) IS NOT NULL);


--
-- Name: transaction_id_index; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX transaction_id_index ON reclada.object USING btree (transaction_id);


--
-- Name: triggers_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX triggers_index_v47 ON reclada.object USING gin (((attributes -> 'triggers'::text))) WHERE ((attributes -> 'triggers'::text) IS NOT NULL);


--
-- Name: width_index_v47; Type: INDEX; Schema: reclada; Owner: -
--

CREATE INDEX width_index_v47 ON reclada.object USING btree (((attributes -> 'width'::text))) WHERE ((attributes -> 'width'::text) IS NOT NULL);


--
-- Name: staging load_staging; Type: TRIGGER; Schema: reclada; Owner: -
--

CREATE TRIGGER load_staging AFTER INSERT ON reclada.staging REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION reclada.load_staging();


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
-- Name: v_object_unifields; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_object_unifields;


--
-- Name: v_user; Type: MATERIALIZED VIEW DATA; Schema: reclada; Owner: -
--

REFRESH MATERIALIZED VIEW reclada.v_user;


--
-- PostgreSQL database dump complete
--

