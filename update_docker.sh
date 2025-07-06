#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker pull ghcr.io/maplibre/martin
docker container rm -f martin
docker run --name martin \
	--net=host \
	--restart=always --detach -p 3000:3000 -v ${SCRIPT_DIR}/config/:/config \
	ghcr.io/maplibre/martin --config config/config.yaml
