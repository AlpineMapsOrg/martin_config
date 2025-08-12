#!/bin/sh

# clear output dir
rm out/*

# update docker (to remove possible caching)
../update_docker.sh >/dev/null

# wait for a few seconds so that the server can restart
sleep 10

# request urls listed in the sample.txt 
# time command before wget gives us the duration of the task
# time --format "%Eelapsed" --quiet wget -i simple_sample.txt -P out/ --quiet
time --format "%Eelapsed" --quiet wget -i hohe_tauern_sample.txt -P out/ --quiet


