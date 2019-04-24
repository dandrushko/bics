#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


function download() {

   url=$1
   name=$2

   if [ -f "`pwd`/${name}" ]; then
        echo "`pwd`/${name} already exists, No need to download"
   else
        # download to given directory
        echo "Downloading ${url} to `pwd`/${name}"

        set +e
        curl_cmd=$(which curl)
        wget_cmd=$(which wget)
        set -e

        if [[ ! -z ${curl_cmd} ]]; then
            curl -L -o ${name} ${url}
        elif [[ ! -z ${wget_cmd} ]]; then
            wget -O ${name} ${url}
        else
            echo "Failed to download ${url}: Neither 'cURL' nor 'wget' were found on the system"
            exit 1;
        fi
   fi

}

function download_nodecellar() {

   url=$1
   name=$2

   if [ -f "`pwd`/${name}" ]; then
        echo "`pwd`/${name} already exists, No need to download"
   else
        # download to given directory
        echo "Downloading ${url} to `pwd`/${name}"

        set +e
        curl_cmd=$(which curl)
        wget_cmd=$(which wget)
        set -e

        if [[ ! -z ${curl_cmd} ]]; then
            curl -L -o ${name} ${url}
        elif [[ ! -z ${wget_cmd} ]]; then
            wget -O ${name} ${url}
        else
            echo "Failed to download ${url}: Neither 'cURL' nor 'wget' were found on the system"
            exit 1;
        fi
   fi

}

function untar() {

    tar_archive=$1
    destination=$2

    inner_name=$(tar -tf "${tar_archive}" | grep -o '^[^/]\+' | sort -u)

    if [ ! -d ${destination} ]; then
        echo "Untaring ${tar_archive}"
        tar -xf ${tar_archive}

        echo "Moving ${inner_name} to ${destination}"
        mv ${inner_name} ${destination}
    fi
}

function extract_nodecellar() {

    archive=$1
    destination=$2

    if [ ! -d ${destination} ]; then

        if [[ ${archive} == *".zip"* ]]; then

            set +e
            unzip_cmd=$(which unzip)
            set -e

            if [[ -z ${unzip_cmd} ]]; then
                echo "Cannot extract ${archive}: 'unzip' command not found"
                exit 1
            fi
            inner_name=$(unzip -qql "${archive}" | sed -r '1 {s/([ ]+[^ ]+){3}\s+//;q}')
            echo "Unzipping ${archive}"
            unzip ${archive}

            echo "Moving ${inner_name} to ${destination}"
            mv ${inner_name} ${destination}

        else

            # assuming tarball if the archive is not a zip.
            # we dont check that tar exists since if we made it
            # this far, it definitely exists (nodejs used it)
            inner_name=$(tar -tf "${archive}" | grep -o '^[^/]\+' | sort -u)
            echo "Untaring ${archive}"
            tar -zxvf ${archive}

            echo "Moving ${inner_name} to ${destination}"
            mv ${inner_name} ${destination}

        fi
    fi
}

function get_response_code() {

    port=$1

    set +e

    curl_cmd=$(which curl)

    if [[ ! -z ${curl_cmd} ]]; then
        response_code=$(curl -s -o /dev/null -w "%{http_code}" http://10.10.6.30:${port})
    else
        echo "Failed to retrieve response code from http://localhost:${port}: Neither 'cURL' nor 'wget' were found on the system"
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
        echo "[GET] http://10.10.6.30:${port} ${response_code}"
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

TEMP_DIR='/opt'
NODEJS_TARBALL_NAME='node-v6.9.1-linux-x64.tar.xz'

################################
# Directory that will contain:
#  - NodeJS binaries
################################
NODEJS_ROOT=${TEMP_DIR}/nodejs
NODEJS_BINARIES_PATH=${NODEJS_ROOT}/nodejs-binaries
mkdir -p ${NODEJS_ROOT}

cd ${TEMP_DIR}
download https://nodejs.org/dist/v6.9.1/${NODEJS_TARBALL_NAME} ${NODEJS_TARBALL_NAME}
untar ${NODEJS_TARBALL_NAME} ${NODEJS_BINARIES_PATH}

echo "Fixing node path in npm-cli.js..."
NPM_CLI_PATH=${NODEJS_BINARIES_PATH}/lib/node_modules/npm/bin/npm-cli.js
NPM_CLI_FIRST_LINE="\#\!${NODEJS_BINARIES_PATH}/bin/node"
sed -i "1s/.*/${NPM_CLI_FIRST_LINE//\//\\/}/" ${NPM_CLI_PATH}

echo "Sucessfully installed NodeJS"

NODEJS_BINARIES_PATH=${TEMP_DIR}/nodejs/nodejs-binaries
APPLICATION_URL='https://github.com/cloudify-cosmo/nodecellar/archive/master.tar.gz'
AFTER_SLASH=${APPLICATION_URL##*/}
NODECELLAR_ARCHIVE_NAME=${AFTER_SLASH%%\?*}

################################
# Directory that will contain:
#  - Nodecellar source
################################
NODECELLAR_ROOT_PATH=${TEMP_DIR}/nodecellar
NODECELLAR_SOURCE_PATH=${NODECELLAR_ROOT_PATH}/nodecellar-source
mkdir -p ${NODECELLAR_ROOT_PATH}

cd ${TEMP_DIR}
download_nodecellar ${APPLICATION_URL} ${NODECELLAR_ARCHIVE_NAME}
extract_nodecellar ${NODECELLAR_ARCHIVE_NAME} ${NODECELLAR_SOURCE_PATH}

cd ${NODECELLAR_SOURCE_PATH}
echo "Installing nodecellar dependencies using npm"
${NODEJS_BINARIES_PATH}/bin/npm install


echo "Sucessfully installed nodecellar"


### Launching nodecellar
NODEJS_BINARIES_PATH="/opt/nodejs/nodejs-binaries"
NODECELLAR_SOURCE_PATH="/opt/nodecellar/nodecellar-source"
STARTUP_SCRIPT="server.js"

COMMAND="${NODEJS_BINARIES_PATH}/bin/node ${NODECELLAR_SOURCE_PATH}/${STARTUP_SCRIPT}"

export APP_HOST="10.10.6.20"
export NODECELLAR_PORT="8080"
export MONGO_HOST="10.10.6.30"
export MONGO_PORT="27017"



MONGO_REST_PORT=`expr ${MONGO_PORT} + 1000`
wait_for_server ${MONGO_REST_PORT} 'MongoDB'

nohup ${COMMAND} > /dev/null 2>&1 &

sed -i s/exit\ 0//g /etc/rc.local
echo ${COMMAND} >> /etc/rc.local
echo "exit 0" >> /etc/rc.local

echo "Nodecellar app was started"
