import sys
from update_db import DBHelper
from update_db import get_version_from_commit
from update_db import rmdir
from update_db import MAX_VERSION


import os
import os.path

RECLADA_USER_NAME = 'reclada'


def db_install(db_helper:DBHelper = None):

    if db_helper is None:
        db_helper = DBHelper()
    db_helper.json_schema_install()
    db_helper.clone_db()
    
    h = db_helper.get_commit_history()
    max_dump_commit = min(db_helper.config_version,len(h))-1
    while(max_dump_commit > -1):
        c = h[max_dump_commit]
        commit_ver = get_version_from_commit(c)
        installer_ver = get_version_from_commit(c,'install_db.sql')
        if commit_ver == installer_ver:
            break
        else:
            max_dump_commit -= 1
    
    if max_dump_commit > 0:
        os.chdir('update')
        db_helper.run_file('install_db.sql') # exec install_db.py
        db_helper.install_component_db()
        os.chdir('..')

    need_update = not((max_dump_commit == db_helper.config_version - 1) 
        or (db_helper.config_version == MAX_VERSION and max_dump_commit == len(h)-1))

    os.chdir('..')
    rmdir('db')
    return need_update


if __name__ == "__main__":

    if len(sys.argv) > 1:
        arg1 = sys.argv[1]
        db_helper = DBHelper(db_uri = arg1)
    else:
        db_helper = DBHelper() # read update_config.json
        arg1 = ''

    db_helper.recreate_db()
    need_update = db_install(db_helper)

    if need_update:
        raise Exception('Required version are not installed!')

    db_helper.install_components()