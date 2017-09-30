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
    if [ $# -lt 2 ]; then
        printf "["`$DATE`" Info] $1\n" | awk '{$1=$1};1' | tee -a $KON_LOG_FILE
    else
        MSG="$2 $3 $4 $5 $6 $7 $8 $9"
        printf "["`$DATE`" $1] $MSG\n" | awk '{$1=$1};1' | tee -a $KON_LOG_FILE
    fi
}

common::check_root () {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root"
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
    docker rm -f `docker ps -q` > /dev/null 2>&1
}