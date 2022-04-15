from update_db import get_cmd_install_component_db, CURRENT_DIR
import os

if __name__ == "__main__":

    if not os.path.exists('up_script.sql'):
        os.chdir(CURRENT_DIR)

    try:
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

    except Exception as e:
        input(str(e))

