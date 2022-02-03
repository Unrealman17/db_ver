from json.decoder import JSONDecodeError
from update_db import get_version_from_commit, get_version_from_db,clone_db,install_components,clear_db_from_components
from update_db import run_file, psql_str,rmdir,run_test,run_cmd_scalar,downgrade_test,run_object_create,pg_dump

import os
import datetime
import json


def upgrade():
    res = os.popen('python create_up.sql.py').read()

    if res != 'Done\n':
        raise Exception(f'create_up.sql.py error: {res}')

    run_file('up.sql')

if __name__ == "__main__":

    install_components()
    t = str(datetime.datetime.now())
    
    down_test = downgrade_test

    downgrade_dump = 'downgrade_dump.sql'
    current_dump = path = os.path.join('db','update','install_db.sql')

    commit_ver = get_version_from_commit()
    try:
        db_ver = get_version_from_db()
        install_db = commit_ver != db_ver + 1
    except ValueError:
        # if database does not exist
        install_db = True
    if install_db:
        os.system('python install_db.py')
        if down_test:
            if run_object_create:
                input('run_object_create must be false for downgrade_test')
                down_test = False
            else:
                print('trying to find dump of current version...')
                clone_db()
                os.chdir('..')
                if os.path.isfile(current_dump):
                    print('success!')
                else:
                    print('dump not found...')
                    print('pg_dump for current version...')
                    current_dump = 'current_dump.sql'
                    pg_dump(current_dump,t)
    else:
        print('install_db.py skipped, database has actual version')
        down_test = False
    
    input("Press Enter to apply new version . . .")

    upgrade()

    if down_test:
        run_cmd_scalar('select dev.downgrade_version();')
        print('pg_dump after downgrade version...')
        pg_dump(downgrade_dump,t)
        with open(downgrade_dump, encoding='utf8') as dd, open(current_dump, encoding='utf8') as cd:
            ldd = dd.readlines() #lines from downgrade_dump
            lcd = cd.readlines() #lines from current_dump

        skip = 2 # update_db.pg_dump
        d = []
        copy = False
        skipCopy = False
        if len(ldd) < len(lcd): 
            input("!!! down.sql invalid !!! downgrade dump shorter then current . . .")
        else:
            j = -1 #lcd
            i = -1 #ldd
            while i + 1 < len(ldd):
                i += 1
                j += 1
                if skip > 0:
                    skip-=1
                    continue
                if not copy:
                    copy = ldd[i].startswith('COPY ')
                    if ldd[i].startswith('COPY reclada.unique_object') or ldd[i].startswith('COPY reclada.field'):
                        skipCopy = True
                    else:
                        if copy:
                            sc = set()
                            sd = set()
                        suffix = ", true);\n"
                        for prefix in ["SELECT pg_catalog.setval('dev.ver_id_seq',","SELECT pg_catalog.setval('reclada."]:
                            if (ldd[i].startswith(prefix)
                                and lcd[j].startswith(prefix)
                                and ldd[i].endswith(suffix)
                                and lcd[j].endswith(suffix)):
                                break
                        else:
                            if (ldd[i] != lcd[j]):
                                good = False
                                while (ldd[i] != lcd[j]):
                                    if ldd[i].startswith('CREATE INDEX '):
                                        good = True
                                    i += 1
                                    if i == len(ldd):
                                        input("!!! down.sql invalid !!! (max i)")
                                        good = False
                                        break
                                if not good:
                                    d.append(ldd[i])
                                    input("!!! down.sql invalid !!! found new unexpected db-object")
                                    break

                else: # COPY
                    if ldd[i] == '\n' or lcd[j] == '\n':
                        copy = False
                        if skipCopy:
                            while (ldd[i] != '\n'):
                                i += 1
                                if i == len(ldd):
                                    input("!!! down.sql invalid !!!")
                                    break
                            skipCopy = False
                            continue
                        if sc != sd:
                            input("!!! down.sql invalid !!! table data has changed . . .")
                            break
                    else:
                        if skipCopy:
                            continue
                        sd.add(ldd[i])
                        sc.add(lcd[j])
            if len(d)>0:
                print("down.sql invalid:")
                for i in range(0,len(d),2):
                    print(d[i] + d[i+1])
                input("!!! down.sql invalid !!! Enter to continue . . .")
            else:
                print("\n\nOK: down.sql valid\n\n")

            
        os.remove(downgrade_dump)
        os.remove(current_dump)
        rmdir('db')
        os.system('python install_db.py')
        upgrade()
    else:
        print("skipped downgrade test...")
    input("Press Enter to update jsonschemas and install_db.sql . . .")

    if install_db:
        print('clear db from components...')
        clear_db_from_components()
        print('pg_dump...')
        pg_dump('install_db.sql',t)

        print('loading jsonschemas..')
        sc = os.popen(psql_str('-c "SELECT for_class,attrs FROM reclada.v_class;"')).readlines()
        rmdir('jsonschema')
        os.makedirs('jsonschema')
        os.chdir('jsonschema')
        for s in sc:
            try:
                for_class, attrs = s.replace('\n',' ').split(' | ')
                attrs = json.dumps(json.loads(attrs),sort_keys=True,indent=4)
                for_class = for_class.strip()
            except Exception as e:
                if type(e) in [JSONDecodeError,ValueError]:
                    continue
                else:
                    raise e
            with open(f'{for_class}.json','a') as f:
                f.write(attrs)
        os.chdir('..')
    else:
        print('skipped . . .')
        print('If evrything okay - run this script again before commit to update jsonschemas and install_db.sql')
    
    input("Press Enter to install components . . .")
    install_components()

    input("Press Enter to run testing . . .")    
    run_test()
