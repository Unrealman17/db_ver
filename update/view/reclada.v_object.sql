-- drop VIEW if EXISTS reclada.v_object;
CREATE OR REPLACE VIEW reclada.v_object
AS
    SELECT  
            t.id            ,
            t.GUID as obj_id,
            t.class         ,
            t.created_time       ,
            t.attributes as attrs,
            cl.for_class as class_name,
            cl.default_value,
            (
                select json_agg(tmp)->0
                    FROM 
                    (
                        SELECT  t.GUID       as "GUID"              ,
                                t.class      as "class"             ,
                                t.active     as "active"            ,
                                t.attributes as "attributes"        ,
                                t.transaction_id as "transactionID" ,
                                t.parent_guid as "parentGUID"       ,
                                t.created_time as "createdTime"
                    ) as tmp
            )::jsonb as data,
            t.active,
            t.transaction_id,
            t.parent_guid
        FROM reclada.object t
        left join reclada.v_class_lite cl
            on cl.obj_id = t.class
;

-- select * from reclada.v_object where revision is not null


