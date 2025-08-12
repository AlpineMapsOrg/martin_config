#!/bin/bash

cd "$(dirname "$0")"

curl -A "Mozilla/5.0" \
     -H "Accept: application/json" \
     --compressed \
     -o panomax.json \
     "https://api.panomax.com/1.0/maps/panomaxweb"
wget -O feratel.json "https://www.feratel.com/index.php?type=123457"
wget -O it_wms.json "https://www.it-wms.com/wp-content/themes/wmsweb/assets/locations/mdata.json"
wget -O foto-webcam.json "https://www.foto-webcam.eu/webcam/include/metadata.php"

echo "panomax"
python3 convert.py panomax panomax.json
echo "feratel"
python3 convert.py feratel feratel.json
echo "itwms"
python3 convert.py itwms it_wms.json
echo "foto-webcam"
python3 convert.py foto-webcam foto-webcam.json
echo "done"
