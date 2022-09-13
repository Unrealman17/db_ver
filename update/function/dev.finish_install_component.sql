
DROP FUNCTION IF EXISTS dev.finish_install_component;
CREATE OR REPLACE FUNCTION dev.finish_install_component()
RETURNS text AS $$
DECLARE
    _f_name   text := 'dev.finish_install_component';
    _count    text := '';
    _parent_component_name text;
    _comp_obj jsonb;
    _data     jsonb;
	_tran_id  bigint := reclada.get_transaction_id();
BEGIN

    perform reclada.raise_exception('Component does not found.',_f_name)
        where not exists(select 1 from dev.component);
    
    select jsonb_build_object(
                                'GUID'          , guid::text,
                                'class'         , 'Component',
                                'transactionID' , _tran_id,
                                'attributes'    , jsonb_build_object(
                                    'name'        , name,
                                    'repository'  , repository,
                                    'commitHash'  , commit_hash
                                )
                            ),
            parent_component_name
        from dev.component
        into _comp_obj,
             _parent_component_name;

    delete from dev.component;

    select count(*) 
        from dev.component_object
            where status = 'need to check'
        into _count;

    perform reclada.raise_notice('To delete: '|| _count ||' objects');

    update dev.component_object
        set status = 'delete'
            where status = 'need to check';

    update dev.component_object
        set data = data 
                    || jsonb_build_object('transactionID',_tran_id)
                    || jsonb_build_object('parentGUID',(_comp_obj  ->>'GUID')::uuid)
            where status != 'delete';

    perform reclada_object.delete(data)
        from dev.component_object
            where status = 'delete';

    FOR _data IN (SELECT data 
                    from dev.component_object 
                        where status = 'create_subclass'
                        ORDER BY id)
    LOOP
        perform reclada_object.create_subclass(_data);
    END LOOP;

    perform reclada_object.create(c.data) v
        from dev.component_object c
            where c.status = 'create';

    perform reclada_object.update(data)
        from dev.component_object
            where status = 'update';

    if exists
    (
        select 
            from reclada.object o
                where o.guid = (_comp_obj->>'GUID')::uuid
    ) then
        perform reclada_object.update(_comp_obj);
    else
        perform reclada_object.create(_comp_obj);
    end if;

    perform reclada_object.refresh_mv('All');

    return 'OK';

END;
$$ LANGUAGE PLPGSQL VOLATILE;
