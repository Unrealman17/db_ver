DROP VIEW if EXISTS public.v_cat;
CREATE OR REPLACE VIEW public.v_cat
AS
    SELECT  vo.obj_id as guid,
            vo.data #>> '{attributes,name}' as name,
            (vo.data #>> '{attributes,weight}')::int as weight,
            vo.data #>> '{attributes,color}' as color
        FROM reclada.v_active_object vo 
            WHERE vo.class_name = 'Cat';
