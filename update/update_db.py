import os
import json
import stat
from pathlib import Path, PurePath
import subprocess
import sys
import urllib.parse
import uuid
import shutil

MAX_VERSION = 999999999
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))

class DBHelper:

    def __init__(self, path = '', db_uri = ''):
        
        self.branch_db = ''
        self.branch_QAAutotests = ''
        self.components = []
        self.config_version = 'latest'
        self.quick_install = True
        self.downgrade_test = True
        if path == '':
            path = CURRENT_DIR
        os.chdir(path)
        if db_uri != '':
            self.db_uri = db_uri
        else:
            j = ''
            with open('update_config.json') as f:
                j = f.read()
            j = json.loads(j)

            self.db_uri = j["db_URI"]

            parsed = urllib.parse.urlparse(self.db_uri)
            self.db_uri = self.db_uri.replace(parsed.password, urllib.parse.quote(parsed.password))

            self.branch_db = j["branch_db"]
            self.branch_QAAutotests = j["branch_QAAutotests"]
            self.components = j["components"]
            self.config_version = j["version"]
            self.quick_install = j["quick_install"]
            self.downgrade_test = j["downgrade_test"]

        if self.config_version == 'latest':
            self.config_version = MAX_VERSION
        else:
            self.config_version = int(self.config_version)

        parsed = urllib.parse.urlparse(self.db_uri)
        self.db_user = parsed.username
        self.db_name = self.db_uri.split('/')[-1]
        self.remote = get_current_remote_url()

    def clone_db(self):
        clone('db', self.remote, self.branch_db)

    def get_commit_history(self, need_comment:bool = False):
        checkout(self.branch_db)
        
        res = os.popen(f'git log --pretty=format:"%H" --first-parent b47dfd1ee2a25917bc5614b59674450a19c8a023..').readlines()
        for i in range(len(res)):
            res[i]=res[i].strip()
        res.reverse()
        if need_comment:
            res2 = os.popen('git log --pretty=format:"%B" --first-parent b47dfd1ee2a25917bc5614b59674450a19c8a023..').readlines()
            while('\n' in res2):
                res2.remove('\n')
            for i in range(len(res2)):
                s = res2[i]
                res2[i] = s=s[s.find('(')+1:s.find(')')]
            res2.reverse()

        pre_valid_commit = 0
        i = 0
        remove_index = []
        for commit in res[:]:
            commit_v = get_version_from_commit(commit)
            os.chdir('update')
            # validate commit_v
            if pre_valid_commit + 1 == commit_v:
                pre_valid_commit +=1
            else:
                remove_index.append(i)
                print(f'\tcommit: {commit} is invalid')
            i+=1
            os.chdir('..')
            
        for i in reversed(remove_index):
            del res[i]
            if need_comment:
                del res2[i]

        if need_comment:
            return res, res2

        return res

    def psql_str(self, cmd:str , db_uri = '')->str:
        if db_uri == '':
            db_uri = self.db_uri
        return f'psql -v ON_ERROR_STOP=1 -t -P pager=off {cmd} {db_uri}'

    def pg_dump(self, file_name:str, time:str):
        self.run_cmd_scalar('delete from dev.component_object;')

        os.system(f'pg_dump -f {file_name} -O {self.db_uri}')

        with open('up_script.sql',encoding='utf8') as f:
            ver_str = f.readline()
            ver = int(ver_str.replace('-- version =',''))
                
        with open(file_name,encoding='utf8') as f:
            scr_str = f.readlines()

        with open(file_name,'w',encoding='utf8') as f:
            f.write(ver_str)
            f.write(f'-- {time}')
            for line in scr_str:
                if line.find('GRANT') != 0 and line.find('REVOKE') != 0:
                    f.write(line)

    def run_file(self, file_name):
        cmd = self.psql_str(f'-f "{file_name}"')
        subprocess.run(cmd, check=True)
        # return self.run_cmd(cmd)
        # os.system(cmd)

    def json_schema_install(self):
        file_name = 'patched.sql'
        clone('postgres-json-schema','https://github.com/gavinwahl/postgres-json-schema.git')
        with open('postgres-json-schema--0.1.1.sql') as s, open(file_name,'w') as d:
            d.write(s.read().replace('@extschema@','public').replace('CREATE OR REPLACE FUNCTION ','CREATE OR REPLACE FUNCTION public.'))

        self.run_file(file_name)
        os.chdir('..')
        rmdir('postgres-json-schema')

    def install_component_db(self):
        # if self.config_version < 48: # Components do not exist before 48
        #     raise Exception('Version lower 48 is not allowed')
        file_name = 'object_create_patched.sql'
        
        with open(file_name,'w') as f:
            f.write(get_cmd_install_component_db())

        self.run_file(file_name)
        os.remove(file_name)

    def run_cmd_scalar(self, command, db_uri  = '')->str:
        command = command.replace('"', "'||chr(34)||'").replace('\n', ' ')
        cmd = self.psql_str(f'-c "{command}"', db_uri)
        return self.run_cmd(cmd)

    def run_cmd(self, cmd):
        proc = subprocess.run(cmd, capture_output=True)
        err = proc.stderr.decode("utf-8").strip()
        if proc.returncode != 0:
            err = err.strip()
            print(err)
            raise subprocess.CalledProcessError(
                proc.returncode, cmd, proc.stdout, proc.stderr)
        res = proc.stdout.decode("utf-8").strip() + '\n' + err
        return res.strip()

    def get_component_guid(self, name:str)->str:
        return self.run_cmd_scalar(f"SELECT guid FROM reclada.v_component WHERE name = '{name}'")

    def replace_component(self, path:str, parent_component_name:str = '')->str:
        '''
            replace or install reclada-component
        '''
        name = path.split('/')[-1]
        print(f'installing component "{name}"...')
        getcwd = os.getcwd()

        guid = self.get_component_guid(name)

        repo_hash = get_repo_hash(path)
        #folder: repos/component_name
        if guid != '':
            db_hash = self.run_cmd_scalar(f"SELECT commit_hash FROM reclada.v_component WHERE guid = '{guid}'")
            if db_hash == repo_hash and db_hash != '':
                print(f'Component {name} has actual version')
                os.chdir(getcwd)
                return
        repository = get_current_remote_url()
        
        if parent_component_name != '':
            parent_component_name = f",'{parent_component_name}'::text"
        cmd = f"SELECT dev.begin_install_component('{name}'::text,'{repository}'::text,'{repo_hash}'::text{parent_component_name});"
        res = self.run_cmd_scalar(cmd)
        if res == 'OK':
            f_name = 'configuration.json'
            if not os.path.exists(f_name):
                shutil.copyfile('configuration_default.json', f_name)
            j = ''
            with open(f_name) as f:
                j = f.read()
            j = json.loads(j)
            parametres = j["parametres"]
            installer =  j["installer"]
            components =  j.setdefault('components', [] )

            if installer['type'] == 'psql_script':
                self.psql_script_installer(installer.setdefault('directory',''), installer['files'], parametres)
            else:
                raise Exception(f'installer type: "{installer["type"]}" invalid (component: {name})')
        
            cmd = "SELECT dev.finish_install_component();"
            res = self.run_cmd_scalar(cmd)
            if res != 'OK':
                raise Exception('Component does not installed')
            for p in components:
                self.replace_component(p, name)

        os.chdir(getcwd)

    def psql_script_installer(self, directory:str, files:list, parametres:dict):
        if directory != '':
            cur_dir = os.getcwd()
            os.chdir(PurePath(directory))

        for file_name in files:
            with open(file_name, encoding='utf8') as f:
                obj_cr = f.read()

            for key, value in parametres.items():
                obj_cr = obj_cr.replace(f'#@#{key}#@#', value)

            file_name_patched = f'{file_name}_patched.sql'
            with open(file_name_patched,'w',encoding='utf8') as f:
                f.write(obj_cr)

            self.run_file(file_name_patched)
            os.remove(file_name_patched)
        
        if directory != '': 
            os.chdir(cur_dir)
    
    def get_version_from_db(self)->int:
        return int(self.run_cmd_scalar("select max(ver) from dev.ver;"))

    def recreate_db(self):
        splt = self.db_uri.split('/')
        splt[-1] = 'postgres'
        db_URI_postgres = '/'.join(splt)
        
        def execute(cmd:str):
            self.run_cmd_scalar(cmd, db_URI_postgres)
        
        execute(f'''REVOKE CONNECT ON DATABASE {self.db_name} FROM PUBLIC, {self.db_user};''')
        execute(f'''SELECT pg_terminate_backend(pid)        
                        FROM pg_stat_activity               
                        WHERE pid <> pg_backend_pid()   
                            AND datname = '{self.db_name}';''')
        execute(f'''DROP DATABASE {self.db_name};''')
        execute(f'''CREATE DATABASE {self.db_name};''')
        
    def install_components(self):
        for comp_name in self.components:
            self.replace_component(comp_name)

    def clear_db_from_components(self):
        print('clear db from components...')
        res = self.run_cmd_scalar('''DO
                                $do$
                                DECLARE
                                    _objs  jsonb[];
                                BEGIN
                                    SELECT array_agg(distinct obj_data)
                                        FROM reclada.v_component_object o
                                        INTO _objs;
                                    
                                    PERFORM reclada_object.delete(cn)
                                        FROM unnest(_objs) AS cn;
                                END
                                $do$;''')#to delete indexes

        res = self.run_cmd_scalar('''WITH t as (
                                    SELECT object, subject, guid 
                                        FROM reclada.v_relationship
                                            WHERE type = 'data of reclada-component'
                                )
                                DELETE FROM reclada.object 
                                    WHERE guid in 
                                    (   
                                        SELECT object  FROM t
                                        UNION
                                        SELECT subject FROM t
                                        UNION
                                        SELECT guid    FROM t
                                        UNION 
                                        SELECT guid    FROM reclada.v_component
                                    );''')
        print(res)
        res = self.run_cmd_scalar('''DELETE FROM reclada.object 
                                    WHERE guid in 
                                    (
                                        SELECT r.obj_id
                                            FROM reclada.v_revision r
                                    );''')
        print(res)
        res = self.run_cmd_scalar('''UPDATE reclada.object 
                                    SET attributes = attributes - 'revision';''')
        print(res)
        res = self.run_cmd_scalar('''DELETE FROM dev.component_object;''')
        print(res)
        res = self.run_cmd_scalar('''DELETE FROM dev.meta_data;''')
        print(res)
        res = self.run_cmd_scalar('''SELECT reclada_object.refresh_mv('All');''')
        print(res)


def clone(component_name:str, repository:str, branch:str='', debug_db=False):
    # folder: update
    rmdir(component_name)
    os.chdir('..') #folder: db
    os.chdir('..') #folder: repos

    if not (os.path.exists(component_name) and os.path.isdir(component_name)):
        os.system(f'git clone {repository}')
        os.chdir(component_name)
        if branch != '':
            res = checkout(branch)
        # else use default branch
        os.chdir('..')

    if component_name != 'db':
        folder_source = component_name
    
        path_dest = os.path.join('db','update',component_name)

        shutil.copytree(folder_source, path_dest)

        os.chdir(path_dest)
    else:
        os.chdir(os.path.join('db','update'))
        os.system(f'git clone {repository} db')
        os.chdir(component_name)
        if branch != '':
            res = checkout(branch)

    #folder: repos/db/update/component_name

def get_current_remote_url()->str:
    cmd = "git config --get remote.origin.url"
    return os.popen(cmd).read()[:-1]

def get_current_repo_hash()->str:
    cmd = "git log --pretty=format:%H -n 1"
    return os.popen(cmd).read()

def get_repo_hash(path:str):
    # folder: repos/db/update  
    os.chdir(PurePath(path))
    #folder: repos/component_name
    repo_hash = get_current_repo_hash()
    return repo_hash

#{ Components

def get_cmd_install_component_db()->str:
    url = get_current_remote_url()
    with open("object_create.sql", encoding='utf8') as f:
        object_create = f.read()

    return f""" SELECT reclada.raise_notice('Begin install component db...');
                SELECT dev.begin_install_component('db','{url}','{get_current_repo_hash()}');
                {object_create}
                SELECT dev.finish_install_component();"""


def checkout(to:str = None):
    cmd = f'git status'
    r = os.popen(cmd).read()
    if r.find('nothing to commit, working tree clean')<0:
        cmd = f'git clean -fxd -q'
        r = os.popen(cmd).read()
        cmd = f'git checkout . -q'
        r = os.popen(cmd).read()
    if to != '':
        cmd = f'git checkout {to} -q'
        r = os.popen(cmd).read()
    return r

#} Components

def rmdir(top:str): 
    if os.path.exists(top) and os.path.isdir(top):
        for root, dirs, files in os.walk(top, topdown=False):
            for name in files:
                filename = os.path.join(root, name)
                os.chmod(filename, stat.S_IWUSR)
                os.remove(filename)
            for name in dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(top)

def get_version_from_commit(commit = '', file_name = 'up_script.sql')->int:
    if commit != '':
        checkout(commit)
    cd = Path('update').exists()
    if cd:
        os.chdir('update')
    commit_v = -1
    if not Path(file_name).exists():
        return commit_v
    with open(file_name, encoding='utf8') as f:
        for line in f:
            p = '-- version ='
            if line.startswith(p):
                commit_v = int(line.replace(p,''))
                break
    if cd:
        os.chdir('..')
    return commit_v

def run_test(branch_QAAutotests:str):
    clone('QAAutotests', 'https://github.com/reclada/QAAutotests.git', branch_QAAutotests)
    os.system(f'pip install -r requirements.txt')
    os.system(f'pytest '
        + 'tests/components/security/test_database_sql_injections.py '
        + 'tests/components/database '
        + 'tests/components/postgrest '
        + '--alluredir results --log-file=test_output.log')
    os.chdir('..')
    rmdir('QAAutotests')

def create_up():
    upgrade_script = ''
    version = -1
    with open("up_script.sql",encoding = 'utf-8') as f:
        t = f.readline()
        version = int(t.replace("-- version =",''))
        upgrade_script = f.read()

    if version == -1:
        print("version not found")
        print('add first line "-- version = <number>" in "up_script.sql"')
    
    else:
        template = ''
        with open("upgrade_script_template.sql",encoding = 'utf-8') as f:
            template = f.read()

        up = template.replace('/*#@#@#upgrade_script#@#@#*/',upgrade_script)
        up = up.replace('/*#@#@#version#@#@#*/',str(version))

        ucs = get_cmd_install_component_db()
        up = up.replace('/*#@#@#upgrade_component_script#@#@#*/', ucs)

        with open("up.sql",'w', encoding = "utf-8") as f:
            f.write(up)

        print('Done')

if __name__ == "__main__":

    
    if len(sys.argv) > 1:
        db_uri = sys.argv[1]
        path = ''
        if len(sys.argv) > 2:
            path = sys.argv[2]
        db_helper = DBHelper(db_uri = db_uri, path = path)
    else:
        db_helper = DBHelper() # read update_config.json

    db_helper.clone_db()
    cur_ver_db = db_helper.get_version_from_db()
    print(f'current version database: {cur_ver_db}')

    res = db_helper.get_commit_history()
    
    if len(res) == 0:
        print('There is no updates')
    else:
        for commit in res:
            commit_v = get_version_from_commit(commit)
            os.chdir('update')
            if commit_v == cur_ver_db + 1:
                print(f'commit: {commit}\tcommit_version: {commit_v}')
                os.chdir('..')
                os.chdir('..')
                if os.path.exists('update_config.json'):
                    shutil.copyfile('update_config.json', os.path.join('db','update','update_config.json'))
                os.chdir(os.path.join('db','update'))
                create_up()
                print(db_helper.run_file('up.sql'))
                cur_ver_db+=1
            os.chdir('..')

            if cur_ver_db == db_helper.config_version:
                break

    os.chdir('..')
    rmdir('db')
    if cur_ver_db >= 48: # Components do not exist before 48
        db_helper.install_components() #upgrade components
    