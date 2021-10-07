/*
 * Function reclada_object.datasource_insert updates defaultDataSet and creates Job object
 * Added instead of reclada.datasource_insert_trigger_fnc function called by trigger.
 * class_name is the name of class inserted in reclada.object.
 * obj_id is GUID of added object.
 * attributes is attributes of added object.
 * Required parameters:
 *  _class_name - the class of objects
 *  obj_id     - GUID of object
 *  attributes - attributes of added object
 */
CREATE OR REPLACE FUNCTION reclada_object.datasource_insert
(
    _class_name text,
    obj_id     uuid,
    attributes jsonb
)
RETURNS void AS $$
DECLARE
    dataset       jsonb;
    uri           text;
    environment   varchar;
BEGIN
    IF _class_name in 
            ('DataSource','File') THEN

        SELECT v.data
        FROM reclada.v_active_object v
	    WHERE v.attrs->>'name' = 'defaultDataSet'
	    INTO dataset;

        dataset := jsonb_set(dataset, '{attributes, dataSources}', dataset->'attributes'->'dataSources' || format('["%s"]', obj_id)::jsonb);

        PERFORM reclada_object.update(dataset);

        uri := attributes->>'uri';

        SELECT attrs->>'Environment'
        FROM reclada.v_active_object
        WHERE class_name = 'Context'
        ORDER BY created_time DESC
        LIMIT 1
        INTO environment;

        PERFORM reclada_object.create(
            format('{
                "class": "Job",
                "attributes": {
                    "task": "c94bff30-15fa-427f-9954-d5c3c151e652",
                    "status": "new",
                    "type": "%s",
                    "command": "./run_pipeline.sh",
                    "inputParameters": [{"uri": "%s"}, {"dataSourceId": "%s"}]
                    }
                }', environment, uri, obj_id)::jsonb);

    END IF;
END;
$$ LANGUAGE 'plpgsql' VOLATILE;