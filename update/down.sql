-- you can use "--{function/reclada_object.get_schema}"
-- to add current version of object to downgrade script

drop view public.v_green_cat;
--{view/public.v_cat}
--{view/public.v_green_cat}

alter table public.num drop COLUMN val2;
