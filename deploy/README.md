# Deploy to production server

In this folder are the files/configs for the production server for the TU Wien tile server of the AlpineMaps project.

Please note that the password for the postgresql server has been changed to MARTINPASSWORD. Replace this placeholder with the password with the actual password of the database user used. 


## Adding specific features

If you setup the production server from zero by following the [tutorial](https://github.com/AlpineMapsOrg/documentation/blob/main/Labels/markdown/Vector%20tile/Vector%20Tile%20Server%20Setup.md) your next steps should be to execute the queries (located in the queries/ folder of this repo). Order of the queries:

### adding external webcams

Files located in webcamcrawler/out folder.

```
sudo -umartin psql -Umartin gis -f 0_init.sql

# no particular order
sudo -umartin psql -Umartin gis -f feratel_output.sql
sudo -umartin psql -Umartin gis -f itwms_output.sql
sudo -umartin psql -Umartin gis -f panomax_output.sql

```

### adding features

Files located in queries/ folder.

Note:
The current production server uses a slightly different database table layout for the osm data. So if you are still using this version you need to adapt the above mentioned sql files a bit. All necessary adaptations are noted as a comment at the start of the file. 

```
sudo -umartin psql -Umartin gis -f 1_utilities.sql

# no particular order
sudo -umartin psql -Umartin gis -f cities.sql
sudo -umartin psql -Umartin gis -f cottages.sql
sudo -umartin psql -Umartin gis -f peaks.sql
sudo -umartin psql -Umartin gis -f webcams.sql

sudo -umartin psql -Umartin gis -f 99_combine.sql

```


## Applying changes

At the end you have to (re)start the martin server by executing the ```./update_docker.sh``` script.