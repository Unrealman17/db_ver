/*
 * Auxiliary function jsonb_to_text converts a jsonb field to string.
 * Required parameters:
 *  data - the jsonb field
 * Only valid input is expected.
*/

DROP FUNCTION IF EXISTS reclada_object.jsonb_to_text;
CREATE OR REPLACE FUNCTION reclada_object.jsonb_to_text(data jsonb)
RETURNS text AS $$
    SELECT
        CASE
            WHEN jsonb_typeof(data) = 'string' THEN
                format(E'\'%s\'', data#>>'{}')
            WHEN jsonb_typeof(data) = 'array' THEN
                format('ARRAY[%s]',
                    (SELECT string_agg(
                        reclada_object.jsonb_to_text(elem),
                        ', ')
                    FROM jsonb_array_elements(data) elem))
            ELSE
                data#>>'{}'
        END
$$ LANGUAGE SQL IMMUTABLE;