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

    REFRESH MATERIALIZED VIEW reclada.v_class_lite;

END;
$$ LANGUAGE PLPGSQL VOLATILE;