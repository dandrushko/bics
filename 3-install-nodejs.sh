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

