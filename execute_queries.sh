#!/bin/bash

DB_PASSWORD='SOMEPASSWORD'
DB_NAME='alpinemaps'
DB_USER='alpine'
DB_LINUX_USER='postgres'

export PGPASSWORD=$DB_PASSWORD

sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/1_utilities.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/cities.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/cottages.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/peaks.sql

sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f webcamcrawler/out/0_init.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f webcamcrawler/out/feratel_output.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f webcamcrawler/out/itwms_output.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f webcamcrawler/out/panomax_output.sql

sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/webcams.sql
sudo -u${DB_LINUX_USER} -E psql -U${DB_USER} ${DB_NAME} -h localhost -f queries/99_combine.sql
