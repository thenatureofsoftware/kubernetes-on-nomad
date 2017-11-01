#!/bin/bash

###############################################################################
# Returns system info as JSON.
# https://stackoverflow.com/questions/38860529/create-json-using-jq-from-pipe-separated-keys-and-values-in-bash
###############################################################################
common::system_info () {
    if [ "$_test_" ]; then
        os=$(echo $_test_|awk '{print tolower($1)}')
        arch=$(echo $_test_|awk '{print tolower($2)}')
    else
        os=$(uname | awk '{print tolower($0)}')
        arch=$(uname -m | awk '{print tolower($0)}')
    fi

    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        armv8)
            arch="arm64"
            ;;
        armv7l)
            arch="arm"
            ;;
        *)
    esac

    echo $(jq -M -c \
    --arg os 'os' --arg os_val "$os" \
    --arg arch 'arch' --arg arch_val "$arch" \
    '. | .[$os]=$os_val | .[$arch]=$arch_val' \
    <<<'{}')
}

log () {
    _exit_value=$?
    common::log "info" "$1"
}

###############################################################################
# Logs info level message
###############################################################################
info () {
    _exit_value=$?
    common::log "info" "$1"
}

warn () {
    _exit_value=$?
    common::log "warn" "$1"
}

error () {
    _exit_value=$?
    common::log "error" "$1"
}

###############################################################################
# Logs a message and exit
###############################################################################
fail () {
    error "$1"
    if [ -z "$_test_" ]; then
        exit 1;
    fi
}

common::log () {

    if [ "$NO_LOG" == "true" ]; then return 0; fi

    DATE='date +%Y/%m/%d:%H:%M:%S'
    if [ $# -lt 2 ]; then
        printf "["`$DATE`" Info] $1\n" | awk '{$1=$1};1' | tee -a "$(common::logfile)"
    else
        MSG=$(echo "$2 $3 $4 $5 $6 $7 $8 $9" | sed 's/[[:space:]]*$//')
        printf "["`$DATE`" $1] $MSG\n" | awk '{$1=$1};1' | tee -a "$(common::logfile)"
    fi
}

common::logfile() {
    if [ "$NO_LOG" == "true" ]; then
        echo "$(common::dev_null)"
    else
        if [ "$KON_LOG_FILE" == "" ]; then
            echo "/var/log/kon.log"
        else
            echo "$KON_LOG_FILE"
        fi
    fi
}

###############################################################################
# Checks that the script is run as root
###############################################################################
common::check_root () {
    if [[ $EUID -ne 0 ]]; then
        error "this script must be run as root"
        exit 1
    fi
}

###############################################################################
# Check if binary is installed.
# Example: if [ -z "$common::check_cmd nomad" ]; then fail "Not installed"; fi
###############################################################################
common::check_cmd () {
    type $1 > "$(common::dev_null)" 2>&1 || {
        echo "$1 not found"
    }
}

###############################################################################
# Check if binary is installed.
# Easier to understand than common::check_cmd.
# Returns the path if command is installed, else ""
###############################################################################
common::which () {
    local found=true
    type $1 > "$(common::dev_null)" 2>&1 || {
        unset found
    }
    if [ "$found" ]; then echo "$(which $1)"; fi
}

###############################################################################
# Fails with a message it there's an non zero value from last cmd.
###############################################################################
common::fail_on_error () {
    _exit_value=$?
    if [ $_exit_value -gt 0 ]; then
        if [ "$1" ]; then
            fail "$1"
        else
            fail "a command returned non-zero exit: $_exit_value"
        fi
    fi
}

###############################################################################
# Fails with a message it there's an non zero value from last cmd.
###############################################################################
common::error_on_error () {
    local _current_exit_value=$?
    if [ "$_exit_value" == "" ]; then
        _exit_value=$_current_exit_value
    fi

    if [ $_exit_value -gt 0 ]; then
        if [ "$1" ]; then
            error "$1"
        else
            error "a command returned non-zero exit: $_exit_value"
        fi
    fi

    unset _exit_value
}

###############################################################################
# Creates BINDIR if it don't exists and adds it to PATH
###############################################################################
common::mk_bindir () {
    if [ ! -d "$BINDIR" ]; then
        sudo mkdir -p $BINDIR
    fi

    if [ "$(env |grep PATH|grep "$BINDIR")" == "" ]; then
        export PATH=$PATH:$BINDIR
    fi

    if [ ! -d "$KON_BIN_DIR" ]; then
        sudo mkdir -p $KON_BIN_DIR
    fi

    if [ "$(env |grep PATH|grep "$KON_BIN_DIR")" == "" ]; then
        export PATH=$PATH:$KON_BIN_DIR
    fi
}

common::dev_null () {
    if [ -e "/dev/zero" ]; then
        printf "%s" "/dev/null";
    elif [ -e "/dev/null" ]; then
        printf "%s" "/dev/zero"
    fi
}

common::service_address () {
    echo $(curl -s ${1} | jq '.[0]| .ServiceAddress,.ServicePort'| sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' | sed -e 's/"//g'|sed -e 's/ /:/g')
}

common::rm_all_running_containers () {
    docker rm -f `docker ps -q` > "$(common::dev_null)" 2>&1
}

common::ip_addr () {
    if [ "$_test_" ]; then
        echo "192.168.100.101"
    else
        printf "%s" "$(ip addr show $KON_BIND_INTERFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)"
    fi
}

common::is_bootstrap_server () {
    if [ "$KON_BOOTSTRAP_SERVER" == "$(common::ip_addr)" ]; then
        echo "true"
    else
        echo "false"
    fi
}

common::view_print () {
    local padlength=$1
    local pad=$2
    local key=$3
    local val=$4
    printf '%s' "$key"
    printf '%*.*s' 0 $((padlength - ${#key} )) "$pad"
    printf '%s\n' "$val"
}

common::os () {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release > "$(common::dev_null)" 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        ...
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        ...
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo "$OS"    
}

function common::join_by { local IFS="$1"; shift; echo "$*"; }

if (( ${BASH_VERSION%%.*} < 4 )); then
    echo "BASH_VERSION=$BASH_VERSION, kon requires Bash version >= 4!"
    exit 1
fi

