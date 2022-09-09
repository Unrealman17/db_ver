/*
 * Function reclada_object.refresh_mv refreshes materialized views.
 * class_name is the name of class affected by other CRUD functions.
 * Every materialized view here bazed on objects of the same class so it's necessary to refresh MV
 *   when objects of some class changed.
 * Required parameters:
 *  class_name - the class of objects
 */

DROP FUNCTION IF EXISTS reclada_object.refresh_mv;
CREATE OR REPLACE FUNCTION reclada_object.refresh_mv
(
    class_name text
)
RETURNS void AS $$

BEGIN
    CASE class_name
        WHEN 'ObjectStatus' THEN
            REFRESH MATERIALIZED VIEW reclada.v_object_status;
        WHEN 'User' THEN
            REFRESH MATERIALIZED VIEW reclada.v_user;
        WHEN 'jsonschema' THEN
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        WHEN 'uniFields' THEN
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        WHEN 'All' THEN
            REFRESH MATERIALIZED VIEW reclada.v_object_status;
            REFRESH MATERIALIZED VIEW reclada.v_user;
            REFRESH MATERIALIZED VIEW reclada.v_class_lite;
        ELSE
            NULL;
    END CASE;
END;
$$ LANGUAGE PLPGSQL VOLATILE;