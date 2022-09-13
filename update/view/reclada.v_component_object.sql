drop VIEW if EXISTS reclada.v_component_object;
CREATE OR REPLACE VIEW reclada.v_component_object
AS
    SELECT  o.id,
            c.name component_name, 
            c.guid component_guid, 
            o.transaction_id,
            o.class_name, 
            o.obj_id,
            o.data obj_data
        FROM reclada.v_component c
        JOIN reclada.v_active_object o
            ON o.parent_guid = c.guid;
--select * from reclada.v_component_object
