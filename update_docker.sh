#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo $SCRIPT_DIR

docker pull ghcr.io/maplibre/martin
docker container rm -f martin
docker run --name martin \
	--net=host \
	--restart=always --detach -v ${SCRIPT_DIR}/config/:/config \
	ghcr.io/maplibre/martin --config config/config_vector.yaml --webui enable-for-all
