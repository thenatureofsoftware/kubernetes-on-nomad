#!/bin/bash

log () {
    common::log "Info" "$1"
}

info () {
    common::log "Info" "$1"
}

error () {
    common::log "Error" "$1"
}

###############################################################################
# Logs a message and exit                                                     #
###############################################################################
fail() {
    error "$1"
    exit 1
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
        error "This script must be run as root"
        exit 1
    fi
}

common::check_cmd () {
    type $1 >/dev/null 2>&1 || { common::log "This script requires $1 but it's not installed. Installing."; common::install $1; }
}

common::mk_bindir () {
    if [ ! -d "$BINDIR" ]; then
        mkdir -p $BINDIR
    fi

    if [ "$(env |grep PATH|grep '/opt/bin')" == "" ]; then
        export PATH=$PATH:/opt/bin
    fi
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
    elif type lsb_release >/dev/null 2>&1; then
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

common::generate_config_template () {
  info "Generating sample configuration file $KON_CONFIG"
  mkdir -p $KON_INSTALL_DIR
  cat <<EOF > $KON_CONFIG
#!/bin/bash

###############################################################################
# Kubernetes version
###############################################################################
K8S_VERSION=${K8S_VERSION:=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}

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
ETCD_SERVERS=http://127.0.0.1:2379

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
KUBE_APISERVER=192.168.0.1
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
