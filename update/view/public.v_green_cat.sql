DROP VIEW if EXISTS public.v_green_cat;
CREATE OR REPLACE VIEW public.v_green_cat
AS
    SELECT  vo.guid,
            vo.name,
            vo.weight
        FROM public.v_cat vo 
            WHERE vo.color = 'green';
