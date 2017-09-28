#!/bin/bash

log () {
    common::log "Info" "$1"
}

info () {
    common::log "Info" "$1"
}

err () {
    common::log "Error" "$1"
}

common::log () {
    DATE='date +%Y/%m/%d:%H:%M:%S'
    echo "Num of args $#"
    if [ $# -lt 2 ]; then
        printf "["`$DATE`" kubernetes-on-nomad $(hostname) Info] $1\n" | awk '{$1=$1};1' | tee -a $BASEDIR/kubernetes-on-nomad.log
    else
        MSG="$2 $3 $4 $5 $6 $7 $8 $9"
        printf "["`$DATE`" kubernetes-on-nomad $(hostname) $1] $MSG\n" | awk '{$1=$1};1' | tee -a $BASEDIR/kubernetes-on-nomad.log
    fi
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