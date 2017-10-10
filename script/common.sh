#!/bin/bash

log () {
    _exit_value=$?
    common::log "Info" "$1"
}

###############################################################################
# Logs info level message
###############################################################################
info () {
    _exit_value=$?
    common::log "Info" "$1"
}

error () {
    _exit_value=$?
    common::log "Error" "$1"
}

###############################################################################
# Logs a message and exit
###############################################################################
fail() {
    error "$1"
    if [ ! "$_test_" ]; then exit 1; fi
}

common::log () {

    if [ "$NO_LOG" == "true" ]; then return 0; fi

    DATE='date +%Y/%m/%d:%H:%M:%S'
    if [ $# -lt 2 ]; then
        printf "["`$DATE`" Info] $1\n" | awk '{$1=$1};1' | tee -a "$(common::logfile)"
    else
        MSG="$2 $3 $4 $5 $6 $7 $8 $9"
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

common::check_root () {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
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
            fail "A command returned non-zero exit: $_exit_value"
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
            error "A command returned non-zero exit: $_exit_value"
        fi
    fi

    unset _exit_value
}

###############################################################################
# Creates BINDIR if it don't exists and adds it to PATH
###############################################################################
common::mk_bindir () {
    if [ ! -d "$BINDIR" ]; then
        mkdir -p $BINDIR
    fi

    if [ "$(env |grep PATH|grep '/opt/bin')" == "" ]; then
        export PATH=$PATH:/opt/bin
    fi
}

common::dev_null () {
    if [ -e "/dev/zero" ]; then
        printf "%s" "/dev/null";
    elif [ -e "/dev/null" ]; then
        printf "%s" "/dev/zero"
    fi
}

common::install () {
    sudo apt-get update && sudo apt-get install -y $1 && sudo apt-get clean
}

common::service_address () {
    echo $(curl -s ${1} | jq '.[0]| .ServiceAddress,.ServicePort'| sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' | sed -e 's/"//g'|sed -e 's/ /:/g')
}

common::rm_all_running_containers () {
    docker rm -f `docker ps -q` > "$(common::dev_null)" 2>&1
}

common::ip_addr () {
    printf "%s" "$(ip addr show $KON_BIND_INTERFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)"
}

common::is_server () {
    if [ "$(echo $KON_SERVERS | grep $(common::ip_addr))" == "" ]; then
        echo "false"
    else
        echo "true"
    fi
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

common::generate_config_template () {
  info "Generating sample configuration file $KON_CONFIG"
  mkdir -p $KON_INSTALL_DIR
  cat <<EOF > $KON_CONFIG
#!/bin/bash

###############################################################################
# Kubernetes version
###############################################################################
K8S_VERSION=${K8S_VERSION:=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}
CNI_VERSION=${CNI_VERSION:=v0.6.0}

###############################################################################
# kubeadm version
###############################################################################
KUBEADM_VERSION=${KUBEADM_VERSION:=v1.9.0-alpha.1}

###############################################################################
# Consul Bootstrap server
###############################################################################
KON_BOOTSTRAP_SERVER=192.168.1.101
KON_BIND_INTERFACE=enp0s8
KON_SERVERS=172.17.4.101,172.17.4.102,172.17.4.103

###############################################################################
# List of comma separated addresses <scheme>://<ip>:<port>
###############################################################################
ETCD_SERVERS=http://etcd.service.dc1.consul:2379

###############################################################################
# List of etcd initial cluster <name>=<scheme>://<ip>:<port>
###############################################################################
ETCD_INITIAL_CLUSTER=default=http://127.0.0.1:2380

###############################################################################
# Etcd initial cluster token
###############################################################################
ETCD_INITIAL_CLUSTER_TOKEN=etcd-initial-token-dc1

###############################################################################
# List of minions (kubernetes nodes). Must be nomad nodes with node_class
# containing kubelet. Exampel : node_class = "etcd,kubelet"
###############################################################################
KUBE_MINIONS=node1=192.168.0.1,node2=192.168.0.2,node3=192.168.0.3,\
node4=192.168.0.3

###############################################################################
# kube-apiserver advertise address
###############################################################################
KUBE_APISERVER_PORT=6443
KUBE_APISERVER_EXTRA_SANS=kubernetes.service.dc1.consul,kubernetes.service.dc1,kubernetes.service
KUBE_APISERVER_ADDRESS=https://kubernetes.service.dc1.consul:6443

# Weave
#POD_CLUSTER_CIDR=10.32.0.0/16
# Flannel
POD_CLUSTER_CIDR=10.244.0.0/16

###############################################################################
# Remove this variable or set it to false when done configuring.
###############################################################################
KON_SAMPLE_CONFIG=true

EOF
}

kon::kube-proxy-conf () {
    cat <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
  certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    server: https://10.0.2.15:6443
    name: default
    contexts:
    - context:
      cluster: default
      namespace: default
      user: default
      name: default
      current-context: default
      users:
      - name: default
        user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token

EOF
}
