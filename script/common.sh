#!/bin/bash

log () {
    common::log "$1"
}

common::log () {
    DATE='date +%Y/%m/%d:%H:%M:%S'
    printf "["`$DATE`" kubernetes-on-nomad $(hostname)] $1\n" | tee -a $BASEDIR/kubernetes-on-nomad.log
}

common::check_root () {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

common::check_cmd () {
    type $1 >/dev/null 2>&1 || { common::log "This script requires $1 but it's not installed. Installing."; common::install $1; }
}

common::install () {
    sudo apt-get update && sudo apt-get install -y $1 && sudo apt-get clean
}

common::service_address () {
    echo $(curl -s ${1} | jq '.[0]| .ServiceAddress,.ServicePort'| sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' | sed -e 's/"//g'|sed -e 's/ /:/g')
}

common::rm_all_running_containers () {
    docker rm -f `docker ps -q` 1>&2
}