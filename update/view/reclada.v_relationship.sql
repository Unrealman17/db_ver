drop VIEW if EXISTS reclada.v_relationship;
CREATE OR REPLACE VIEW reclada.v_relationship
AS
    SELECT  obj.id            ,
            obj.obj_id              as guid,
            obj.attrs->>'type'      as type,
            (obj.attrs->>'object' )::uuid   as object,
            (obj.attrs->>'subject')::uuid   as subject,
            obj.parent_guid   ,
            obj.created_time  ,
            obj.attrs         ,
            obj.active        ,
            obj.data
	FROM reclada.v_active_object obj
   	WHERE class_name = 'Relationship';
--select * from reclada.v_relationship
