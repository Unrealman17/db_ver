DROP FUNCTION IF EXISTS reclada.create_revision;
CREATE OR REPLACE FUNCTION reclada.create_revision
(
    userid  varchar, 
    branch  uuid, 
    obj     uuid,
    tran_id bigint default reclada.get_transaction_id()
)
RETURNS uuid AS $$
    INSERT INTO reclada.object
        (
            class,
            attributes,
            transaction_id
        )
               
        VALUES
        (
            (reclada_object.get_schema('revision')->>'GUID')::uuid,-- class,
            format                    -- attributes
            (                         
                '{
                    "num": %s,
                    "user": "%s",
                    "dateTime": "%s",
                    "branch": "%s"
                }',
                (
                    select count(*) + 1
                        from reclada.object o
                            where o.GUID = obj
                ),
                userid,
                now(),
                branch
            )::jsonb,
            tran_id
        ) RETURNING (GUID)::uuid;
    --nextval('reclada.reclada_revisions'),
$$ LANGUAGE SQL VOLATILE;
