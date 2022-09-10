DROP FUNCTION IF EXISTS dev.downgrade_component;
CREATE or replace function dev.downgrade_component( 
    _component_name text
)
returns text
LANGUAGE PLPGSQL VOLATILE
as
$$
BEGIN
    CREATE TEMP TABLE del_comp(
        tran_id bigint,
        id bigint,
        guid uuid,
        name text
    );


    insert into del_comp(tran_id, id, guid, name)
        SELECT    transaction_id, id, guid, name  
            from reclada.v_component 
                where name = _component_name;

    DELETE from reclada.object 
        WHERE transaction_id  in (select tran_id from del_comp);

    DELETE from del_comp;

    insert into del_comp(tran_id, id, guid, name)
        SELECT    transaction_id, id, guid, name  
            from reclada.v_component 
                where name = _component_name;
    
    update reclada.object u
        SET active = true
        FROM del_comp c
            WHERE u.transaction_id = c.tran_id
                and NOT EXISTS (
                        SELECT from reclada.object o
                            WHERE o.active 
                                and o.guid = u.guid
                    );

    drop TABLE del_comp;
    return 'OK';
END
$$;