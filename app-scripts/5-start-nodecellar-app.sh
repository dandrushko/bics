#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


function get_response_code() {

    port=$1

    set +e

    curl_cmd=$(which curl)
    wget_cmd=$(which wget)

    if [[ ! -z ${curl_cmd} ]]; then
        response_code=$(curl -s -o /dev/null -w "%{http_code}" http://${APP_HOST}:${port})
    elif [[ ! -z ${wget_cmd} ]]; then
        response_code=$(wget --spider -S "http://localhost:${port}" 2>&1 | grep "HTTP/" | awk '{print $2}' | tail -1)
    else
        ctx logger error "Failed to retrieve response code from http://localhost:${port}: Neither 'cURL' nor 'wget' were found on the system"
        exit 1;
    fi

    set -e

    echo ${response_code}

}

function wait_for_server() {

    port=$1
    server_name=$2

    started=false

    echo "Running ${server_name} liveness detection on port ${port}"

    for i in $(seq 1 120)
    do
        response_code=$(get_response_code ${port})
        echo "[GET] http://${APP_HOST}:${port} ${response_code}"
        if [ ${response_code} -eq 200 ] ; then
            started=true
            break
        else
            echo "${server_name} has not started. waiting..."
            sleep 1
        fi
    done
    if [ ${started} = false ]; then
        echo "${server_name} failed to start. waited for a 120 seconds."
        exit 1
    fi
}

NODEJS_BINARIES_PATH="/opt/nodejs/nodejs-binaries"
NODECELLAR_SOURCE_PATH="/opt/nodecellar/nodecellar-source"
STARTUP_SCRIPT="server.js"

COMMAND="${NODEJS_BINARIES_PATH}/bin/node ${NODECELLAR_SOURCE_PATH}/${STARTUP_SCRIPT}"

#export APP_HOST="10.10.6.25"
#export NODECELLAR_PORT="8080"
#export MONGO_HOST="10.10.6.25"
#export MONGO_PORT="27017"

. app.settings

echo "MongoDB is located at ${MONGO_HOST}:${MONGO_PORT}"
echo "Starting nodecellar application on port ${NODECELLAR_PORT}"

echo "${COMMAND}"
nohup ${COMMAND} > /dev/null 2>&1 &
PID=$!

wait_for_server ${NODECELLAR_PORT} 'Nodecellar'

echo "Sucessfully started Nodecellar (${PID})"
