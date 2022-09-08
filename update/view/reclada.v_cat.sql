DROP VIEW if EXISTS reclada.v_cat;
CREATE OR REPLACE VIEW reclada.v_cat
AS
    SELECT  vo.obj_id as trigger_guid,
            vo.data #>> '{attributes,name}' as name,
            vo.data #>> '{attributes,weight}' as weight,
            vo.data #> '{attributes,color}' as color
        FROM reclada.v_active_object vo 
            WHERE vo.class_name = 'Cat';