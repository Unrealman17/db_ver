For creating new DB migration:
1)  Write upgrade script "up_script.sql". 
    If you need change function or view 
    you should change file in corresponding folder and
    add line in "up_script.sql":
    "\i 'function/reclada_object.get_schema.sql'" - in this case
    we changed function reclada_object.get_schema 
    in file "function/reclada_object.get_schema.sql"
    First line "-- version = 1" in the file up_script.sql is required, 
    here you should set integer number is incremented from previous version.
2)  Write downgrade script in "down.sql" - list of actions,
    which are necessary for change DB state from new state 
    to the state which was before.
    For function or view you can use special comment: 
    "--{function/reclada_object.get_schema}",
    which will be replaced on text of function or view current version from DB.
3)  Run "create_up.sql.py" as result will be created "up.sql" file.
4)  Connect to database via psql client from "update" folder and use 
 	command "\i up.sql" for upgrade database.
	If migration was applied successful you will see:
    - "OK, curren version: <DB version before upgrade>"
    - "OK, curren version: <DB version after upgrade>"
    If you don't see line "OK, curren version: <DB version before upgrade>", that mean
    down.sql is incorrect.
