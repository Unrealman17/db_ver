DROP FUNCTION IF EXISTS reclada_object.get_jsonschema_guid;
CREATE OR REPLACE FUNCTION reclada_object.get_jsonschema_guid()
RETURNS uuid AS $$
    SELECT class
        FROM reclada.object o
            where o.GUID = 
                (
                    select class 
                        from reclada.object 
                            where class is not null 
                    limit 1
                )
$$ LANGUAGE SQL STABLE;