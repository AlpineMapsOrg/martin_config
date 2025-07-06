#!/bin/bash

# install debian dependencies
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections && \
sudo DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
apt-get install -y --no-install-recommends \
postgresql postgis postgresql-postgis osm2pgsql \
-o Dpkg::Options::="--force-confdef" \
-o Dpkg::Options::="--force-confold"

# create database
DB_PASSWORD='SOMEPASSWORD'

SQL_COMMANDS=$(cat <<EOF
CREATE DATABASE alpinemaps;
CREATE USER alpine PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE alpinemaps TO alpine;
\c alpinemaps
ALTER SCHEMA public OWNER TO alpine;
CREATE EXTENSION postgis;
CREATE EXTENSION hstore;
EOF
)

echo "$SQL_COMMANDS" | sudo -u postgres psql postgres

export PGPASSWORD=$DB_PASSWORD


# download osm data
mkdir -p data
wget -O ./data/austria-latest.osm.pbf https://download.geofabrik.de/europe/austria-latest.osm.pbf

# load osm data
osm2pgsql -d alpinemaps -U alpine -H localhost --hstore ./data/austria-latest.osm.pbf
