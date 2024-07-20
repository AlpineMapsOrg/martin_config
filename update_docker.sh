#!/bin/sh


docker pull ghcr.io/maplibre/martin
docker container rm -f martin
docker run --name martin \
	--net=host \
	--restart=always --detach -p 3000:3000 -v /media/Data/Studium/Master/Projects/AlpineMapsOrg/martin/config/:/config \
	ghcr.io/maplibre/martin --config config/config.yaml