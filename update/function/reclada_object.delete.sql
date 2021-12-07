/*
* Function reclada_object.delete updates object with field "isDeleted": true.
 * A jsonb with the following parameters is required.
 * At least one of the following parameters is required:
 *  GUID - the identifier of the object
 *  class - the class of objects
 *  transactionID - object's transaction number. One transactionID is used for a bunch of objects.
 * Optional parameters:
 *  attributes - the attributes of object
 *  branch - object's branch
 *
*/

DROP FUNCTION IF EXISTS reclada_object.delete;
CREATE OR REPLACE FUNCTION reclada_object.delete(data jsonb, user_info jsonb default '{}'::jsonb)
RETURNS jsonb
LANGUAGE PLPGSQL VOLATILE
AS $$
DECLARE
    v_obj_id            uuid;
    tran_id             bigint;
    class               text;
    class_uuid          uuid;
    list_id             bigint[];

BEGIN

    v_obj_id := data->>'GUID';
    tran_id := (data->>'transactionID')::bigint;
    class := data->>'class';

    IF (v_obj_id IS NULL AND class IS NULL AND tran_id IS NULl) THEN
        RAISE EXCEPTION 'Could not delete object with no GUID, class and transactionID';
    END IF;

    class_uuid := reclada.try_cast_uuid(class);

    WITH t AS
    (    
        UPDATE reclada.object u
            SET status = reclada_object.get_archive_status_obj_id()
            FROM reclada.object o
                LEFT JOIN
                (   SELECT obj_id FROM reclada_object.get_GUID_for_class(class)
                    UNION SELECT class_uuid WHERE class_uuid IS NOT NULL
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

    SELECT array_to_json
    (
        array
        (
            SELECT o.data
            FROM reclada.v_object o
            WHERE o.id IN (SELECT unnest(list_id))
        )
    )::jsonb
    INTO data;

    IF (jsonb_array_length(data) <= 1) THEN
        data := data->0;
    END IF;
    
    IF (data IS NULL) THEN
        RAISE EXCEPTION 'Could not delete object, no such GUID';
    END IF;

    PERFORM reclada_object.refresh_mv(class);

    PERFORM reclada_notification.send_object_notification('delete', data);

    RETURN data;
END;
$$;