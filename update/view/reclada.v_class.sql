drop VIEW if EXISTS reclada.v_class;
CREATE OR REPLACE VIEW reclada.v_class
AS
    SELECT  obj.id            ,
            obj.obj_id        ,
            cl.for_class      ,
            cl.version        ,
            obj.created_time  ,
            obj.attrs         ,
            obj.active        ,
            obj.data          ,
            obj.parent_guid   ,
            cl.default_value
	FROM reclada.v_class_lite cl
    JOIN reclada.v_active_object obj
        on cl.id = obj.id;
--select * from reclada.v_class