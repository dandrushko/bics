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

    if [ ! -d ${destination} ]; then
        inner_name=$(tar -tf "${tar_archive}" | grep -o '^[^/]\+' | sort -u)
        echo "Untaring ${tar_archive}"
        tar -zxvf ${tar_archive}

        echo "Moving ${inner_name} to ${destination}"
        mv ${inner_name} ${destination}
    fi
}

function install_mongo_deps() {
	apt -y update
	apt -y install python-pip
	pip install pymongo==2.8.0	    
}


TEMP_DIR='/opt'
MONGO_TARBALL_NAME='mongodb-linux-x86_64-2.4.9.tgz'

MONGO_ROOT_PATH=${TEMP_DIR}/mongodb
MONGO_DATA_PATH=${MONGO_ROOT_PATH}/data
MONGO_BINARIES_PATH=${MONGO_ROOT_PATH}/mongodb-binaries
mkdir -p ${MONGO_ROOT_PATH}

cd ${TEMP_DIR}
download http://downloads.mongodb.org/linux/${MONGO_TARBALL_NAME} ${MONGO_TARBALL_NAME}
untar ${MONGO_TARBALL_NAME} ${MONGO_BINARIES_PATH}

echo "Creating MongoDB data directory in ${MONGO_DATA_PATH}"
mkdir -p ${MONGO_DATA_PATH}

echo "Sucessfully installed MongoDB"

install_mongo_deps

PORT=27017
MONGO_ROOT_PATH="/opt/mongodb"
MONGO_BINARIES_PATH=${MONGO_ROOT_PATH}/mongodb-binaries
MONGO_DATA_PATH=${MONGO_ROOT_PATH}/data
COMMAND="sudo ${MONGO_BINARIES_PATH}/bin/mongod --port ${PORT} --dbpath ${MONGO_DATA_PATH} --rest --journal --shardsvr --smallfiles"

nohup ${COMMAND} > /dev/null 2>&1 &
PID=$!

sed -i s/exit\ 0//g /etc/rc.local
echo ${COMMAND} >> /etc/rc.local
echo "exit 0" >> /etc/rc.local



