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
        guid uuid
    );


    insert into del_comp(tran_id, id, guid)
        SELECT    transaction_id, id, guid  
            from reclada.v_component 
                where name = _component_name;

    DELETE from reclada.object 
        WHERE transaction_id  in (select tran_id from del_comp);

    DELETE from del_comp;

    insert into del_comp(tran_id, id, guid)
        SELECT    transaction_id, id, obj_id  
            from reclada.v_object obj
                WHERE obj.class_name = 'Component'
                    and obj.attrs->>'name' = _component_name
                    ORDER BY ID DESC
                    limit 1;
    
    update reclada.object u
        SET active = true
        FROM del_comp c
            WHERE u.transaction_id = c.tran_id;

    drop TABLE del_comp;
    return 'OK';
END
$$;