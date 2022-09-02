/*
 * Function reclada_object.get_parent_guid returns parent's GUID and name of the parent field.
 * Required parameters:
 *  _data       - data object from create or update method
 *  _class_name - class of object
 */

DROP FUNCTION IF EXISTS reclada_object.get_parent_guid;
CREATE OR REPLACE FUNCTION reclada_object.get_parent_guid(_data jsonb, _class_name text)
RETURNS TABLE (
    prnt_guid         uuid,
    prnt_field        text) AS $$
DECLARE
    _parent_field   text;
    _parent_guid    uuid;
BEGIN
    SELECT parent_field
    FROM reclada.v_parent_field
    WHERE for_class = _class_name
        INTO _parent_field;

    _parent_guid = reclada.try_cast_uuid(_data->>'parentGUID');
    IF (_parent_guid IS NULL AND _parent_field IS NOT NULL) THEN
        _parent_guid = reclada.try_cast_uuid(_data->'attributes'->>_parent_field);
    END IF;

    RETURN QUERY
    SELECT _parent_guid,
        _parent_field;
END;
$$ LANGUAGE PLPGSQL STABLE;