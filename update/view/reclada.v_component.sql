-- drop VIEW if EXISTS reclada.v_component;
CREATE OR REPLACE VIEW reclada.v_component
AS
    SELECT  obj.id            ,
            obj.obj_id              as guid,
            obj.attrs->>'name'      as name,
            obj.attrs->>'repository'   as repository,
            obj.attrs->>'commitHash'   as commit_hash,
            obj.transaction_id,
            obj.created_time  ,
            obj.attrs         ,
            obj.active        ,
            obj.data
	FROM reclada.v_active_object obj
   	WHERE obj.class_name = 'Component';
--select * from reclada.v_component
