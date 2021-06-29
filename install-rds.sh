host=$1
port=$2
database=$3
user=$4

if [ -z $host ]; then
	echo "usage: install-rds.sh <host> [<port>] [<database>] [<user>]"
	exit 1
fi;

if [ -z $port ]; then
	port=5432
fi;

if [ -z $database ]; then
    database="reclada";
fi;
if [ -z $user ]; then
    user=$database;
fi;

rm -R -f postgres-json-schema
git clone https://github.com/gavinwahl/postgres-json-schema.git
pushd postgres-json-schema
sed 's/@extschema@/public/g' postgres-json-schema--0.1.1.sql > patched.sql
echo "Installing postgres-json-schema"
psql --host=$host --port=$port --dbname=$database --username=$user -f patched.sql
popd

echo $user $database

cd src
echo 'Installing scheme.sql'
psql --host=$host --port=$port --dbname=$database --username=$user -f scheme.sql
echo 'Installing functions.sql'
psql --host=$host --port=$port --dbname=$database --username=$user -f functions.sql
echo 'Installing data.sql'
psql --host=$host --port=$port --dbname=$database --username=$user -f data.sql
