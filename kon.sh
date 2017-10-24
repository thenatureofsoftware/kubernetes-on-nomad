#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Installation directory for all scripts.
KON_INSTALL_DIR=${KON_INSTALL_DIR:=/opt/kon}
KON_BIN_DIR=${KON_BIN_DIR:=$KON_INSTALL_DIR/bin}

# Configuration directory
KON_CONFIG_DIR=${KON_CONFIG_DIR:=/etc/kon}

# Certificates and keys
KON_PKI_DIR=$KON_CONFIG_DIR/pki

SCRIPTDIR=$BASEDIR/script
BINDIR=${BINDIR:=/opt/bin}
JOBDIR=$BASEDIR/nomad/job

KON_CONFIG=$KON_CONFIG_DIR/kon.conf
KON_LOG_FILE=${KON_LOG_FILE:=/var/log/kon.log}
K8S_CONFIGDIR=${K8S_CONFIGDIR:=/etc/kubernetes}
K8S_PKI_DIR=${K8S_PKI_DIR:=$K8S_CONFIGDIR/pki}
KON_POD_NETWORK=${KON_POD_NETWORK:=weave}

# Consul
CONSUL_VERSION=${CONSUL_VERSION:=1.0.0}
KON_CONSUL_CONFIG_DIR=${KON_CONSUL_CONFIG_DIR:=/etc/consul}
KON_CONSUL_CONFIG_TLS=$KON_CONSUL_CONFIG_DIR/tls.json

# Nomad
NOMAD_VERSION=${NOMAD_VERSION:=0.7.0-beta1}

MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}
OBJECT_STORE="kube-store"
BUCKET="resources"
ETCD_SERVERS=${ETCD_SERVERS:=""}

konKey="kon"
konConfigKey="$konKey/config"
konPkiKey=$konKey/pki
konPkiCAKey=$konPkiKey/ca

# If state is a nomad job, then the last part should always be
# the name of the job.
stateKey="$konKey/state"
etcdStateKey="$stateKey/etcd"
configStateKey="$stateKey/config"
nomadStateKey="$stateKey/nomad"
certificateStateKey="$stateKey/certificates"
kubeconfigStateKey="$stateKey/kubeconfig"
kubeletStateKey="$stateKey/kubelet"
kubeProxyStateKey="$stateKey/kube-proxy"
kubeApiServerStateKey="$stateKey/kube-apiserver"
kubeSchedulerStateKey="$stateKey/kube-scheduler"
controllerMgrStateKey="$stateKey/kube-controller-manager"
kubernetesStateKey="$stateKey/kubernetes"

kubernetesKey="kubernetes"
kubernetesNetworkKey="$kubernetesKey/network"
kubernetesPodNetworkCidrKey="$kubernetesNetworkKey/pod-network-cidr"
minionKey="$kubernetesKey/minion"
controllerMgrKubeconfigKey="$kubernetesKey/controller-manager/kubeconfig"
schedulerKubeconfigKey="$kubernetesKey/scheduler/kubeconfig"
adminKubeconfigKey="$kubernetesKey/admin/kubeconfig"
minionsKey="$kubernetesKey/minions"
certsKey="$kubernetesKey/certs"
kubeProxyKey="$kubernetesKey/kube-proxy"
kubeProxyClusterCidrKey="$kubeProxyKey/cluster-cidr"

etcdKey="etcd"
etcdServersKey="$etcdKey/servers"
etcdInitialClusterKey="$etcdKey/initial-cluster"
etcdInitialClusterTokenKey="$etcdKey/initial-cluster-token"
etcdServiceKey="$etcdKey/service"

STOPPED="Stopped"
STARTED="Started"
RUNNING="Running"
CONFIGURED="Configured"
NOT_CONFIGURED="NotConfigured"
OK="OK"

###############################################################################
# Source                                                                      #
###############################################################################
source $SCRIPTDIR/arguments.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/common_install.sh
source $SCRIPTDIR/config.sh
source $SCRIPTDIR/pki.sh
source $SCRIPTDIR/consul.sh
source $SCRIPTDIR/nomad.sh
source $SCRIPTDIR/etcd.sh
source $SCRIPTDIR/kubernetes.sh
source $SCRIPTDIR/ssh.sh
source $SCRIPTDIR/cluster.sh

###############################################################################
# Installs kon scripts                                                        #
###############################################################################
kon::install_script () {
    TARGET=$KON_INSTALL_DIR
    printf "%s\n" "installing kubernetes-on-nomad to directory: $TARGET"
    if [ -d "$TARGET/script" ] || [ -f "$TARGET/kon.sh" ]; then
        printf "%s\n" "error: target directory: $TARGET is not empty!"
        return 1
    fi
    
    mkdir -p $TARGET/{script,nomad/job}
    cp $SCRIPTDIR/* $TARGET/script
    cp $JOBDIR/*.nomad $TARGET/nomad/job
    cp $BASEDIR/kon.sh $TARGET/

    chmod a+x $TARGET/script/*.sh
    chmod a+x $TARGET/kon.sh
}

###############################################################################
# Commands:
# generate-config - Generates sample configuration file.
# generate-certificates - Generates all kubernetes certificates.
# generate-kubeconfigs - Generates all kubeconfigs.
###############################################################################

###############################################################################
# Sets up a node.
###############################################################################
setup-node () {
    
    if [ "$(consul::is_running)" ]; then consul::stop; fi
    
    consul::install
    consul::write_tls_config
    
    if [ "$(common::is_bootstrap_server)" == "true" ] && [ ! "$KON_DEV" == "true" ]; then
        info "starting bootstrap consul..."
        consul-start-bootstrap
        info "bootstrap consul started"
    else
        info "starting consul..."
        consul-start
        info "consul started"
    fi
    pki::setup_node_certificates
    nomad::install
    nomad::start
    kubernetes::install

}

###############################################################################
# Generates sample configuration file.
###############################################################################
config-init () {
    if [ -f "$KON_CONFIG" ]; then
        fail "$KON_CONFIG already exists"
    fi
    config::generate_config_template
    info "you can now configure Kubernetes-On-Nomad by editing $KON_CONFIG"
}

all-config () {
    etcd::config
    kubernetes::config
}

all-reset () {
    kubernetes::reset
    etcd::reset
}


all-start () {
  etcd::start
  sleep 5
  kubernetes::start-control-plane
  sleep 5
  kubernetes::start-kubelet
  kubernetes::start-kube-proxy
}

###############################################################################
# Configures etcd 
###############################################################################
etcd-config () {
    # switch log of
    NO_LOG=true
    
    kubernetes-stop

    etcd-stop

    # switch log on
    unset NO_LOG

    etcd::config
}

###############################################################################
# Stopps and removes etcd.
###############################################################################
etcd-reset () {
    etcd::reset
}

###############################################################################
# Starts etcd 
###############################################################################
etcd-start () {
    etcd::start
}

###############################################################################
# Stops etcd 
###############################################################################
etcd-stop () {
    etcd::stop
}

kubernetes-install () {
    kubernetes::install
}

kubernetes-config () {
    kubernetes::config
}

kubernetes-reset () {
    kubernetes::stop
    consul::delete_all $kubernetesKey
    consul::put $certificateStateKey "$NOT_CONFIGURED"
    consul::put $kubeconfigStateKey "$NOT_CONFIGURED"
    rm -rf $K8S_PKI_DIR/*
    rm -rf $K8S_CONFIGDIR/*.*
}

kubernetes-start () {
    kubernetes::start
}

kubernetes-stop () {
    kubernetes::stop
}

###############################################################################
# Environment commands for connecting to nomad.
###############################################################################
nomad-env () {
    nomad::env
}

###############################################################################
# Downloads and installs Nomad in BINDIR.
###############################################################################
nomad-install () {
    nomad::install
}

###############################################################################
# Installs the service unit file and starts nomad
###############################################################################
nomad-start() {
    nomad::start
}

###############################################################################
# Is covered by nomad::start
###############################################################################
nomad-restart() {
    nomad::start
}

###############################################################################
# Stops Nomad
###############################################################################
nomad-stop() {
    nomad::stop
}

###############################################################################
# Downloads and installs Consul in BINDIR.
###############################################################################
consul-install () {
    consul::install
}

consul-start-bootstrap () {
    if [ -z $(which consul) ]; then
        error "please install Consul binaries first (kon install consul)"
        exit 1
    fi

    if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
        info "bootstrap Consul is already running"
    else 
        consul::start-bootstrap
        common::fail_on_error "failed to start consul"

        consul::wait_for_started
    fi

    if [ -f "$_arg_config" ]; then
        config_file=$_arg_config
    else
        config_file=$KON_CONFIG
    fi
    info "$(consul::put_file kon/config $config_file)"
    info "$(consul::put kon/nameserver $kon_nameserver)"
}

consul-start () {
    if [ "$(common::which consul)" == "" ]; then
        fail "please install Consul binaries first (kon consul install)"
    fi
    
    if [ ! "$_arg_bootstrap" == "" ]; then
        KON_BOOTSTRAP_SERVER=$_arg_bootstrap
    fi

    if [ "$KON_BOOTSTRAP_SERVER" == "" ]; then
        error "Consul bootstrap server address required. Please set KON_BOOTSTRAP_SERVER in config or --bootstrap <value> argument"
        exit 1
    fi
    info "bootstrap server address: $KON_BOOTSTRAP_SERVER"

    if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
        info "Consul is already running"
    else 
        consul::start
        common::fail_on_error "failed to start consul"

        consul::wait_for_started
    fi

    if [ ! -f "$KON_CONFIG" ]; then
        mkdir -p $KON_INSTALL_DIR
        
        kon_nameserver=$(consul kv get kon/nameserver)
        if [ $? -gt 0 ]; then fail "failed to get nameserver from kon/nameserver"; fi

        info "reading config from Consul"
        info "$(consul kv get kon/config > $KON_CONFIG)"

        if [ $? -eq 0 ] && [ -f "$KON_CONFIG" ]; then
            info "reloading configuration from Consul."
            source $KON_CONFIG
            info "restarting Consul after new configuration"
            
            consul::stop
            common::fail_on_error "failed to stop consul"

            consul::start
            common::fail_on_error "failed to start consul"

            consul::wait_for_started
        fi
    fi
}

###############################################################################
# Stopps the local Consul agent.
###############################################################################
consul-stop () {
    consul::stop
}

###############################################################################
# Enables all DNS lookups through Consul.
###############################################################################
consul-dns-enable () {
    consul::enable-consul-dns
}

###############################################################################
# Disables all DNS lookups through Consul and restores the original config.
###############################################################################
consul-dns-disable () {
   consul::disable-consul-dns
}

###############################################################################
# Applies kon.conf on all nodes and brings Nomad and Consul up and running
###############################################################################
cluster-apply () {
    info "experimental command that starts the whole cluster"
    cluster::apply
}

###############################################################################
# Shows the state of the cluster
###############################################################################
view-state () {
    # Default view
    declare -A konStates
    konStates=(
                [etcd]="$NOT_CONFIGURED" \
                [consul]="" \
                [config]="" \
                [nomad]="" \
                [certificates]="" \
                [kubeconfig]="" \
                [kubelet]="" \
                [kube-proxy]="" \
                [kube-apiserver]="" \
                [kube-scheduler]="" \
                [kube-controller-manager]="")
    
    # Check if Consul is running
    if consul catalog datacenters > $(common::dev_null) 2>&1; then
        konStates[consul]=$RUNNING

        # Fetch all states
        for stateItem in $(consul kv get -recurse $stateKey); do
            local item=${stateItem//$'\n'}
            konStates[$(echo $item | awk -F '[/:]' '{print $3}')]="$(echo $item | awk -F '[/:]' '{print $4}')"
        done

        if [ "$(dig +short "etcd.service.consul")" ]; then konStates[etcd]=$RUNNING; fi
        if [ "$(dig +short "controller-manager.service.consul")" ]; then konStates[kube-controller-manager]=$RUNNING; fi
        if [ "$(dig +short "scheduler.service.consul")" ]; then konStates[kube-scheduler]=$RUNNING; fi
        if [ "$(dig +short "kubernetes.service.consul")" ]; then
            # Kubernetes is running, now fetch the state of all minions.
            konStates[kubernetes]=$RUNNING
            konStates[kube-apiserver]=$RUNNING

            minions=$(kubectl get nodes -o json)
            for minion in $(echo $minions|jq '.items[].status.addresses[]|select(.type == "Hostname").address'|sed 's/"//g'); do
                konStates[$minionKey/$minion]="$(kubectl get nodes -l "kubernetes.io/hostname=$minion" | sed '2q;d' | awk '{print $2}')"
            done
        fi
    fi

    # If Nomad is running, check job status for kubelet and proxy
    if nomad server-members > $(common::dev_null) 2>&1; then
        konStates[nomad]=$RUNNING
        
        if nomad job status -short kubelet > $(common::dev_null) 2>&1 \
        && [ "$(nomad job status -short kubelet|grep "^Status"|sed 's/ //g'|awk -F '=' '{print $2}')" == "running" ]; then konStates[kubelet]=$RUNNING; fi
        
        if nomad job status -short kube-proxy > $(common::dev_null) 2>&1 \
        && [ "$(nomad job status -short kube-proxy|grep "^Status"|sed 's/ //g'|awk -F '=' '{print $2}')" == "running" ]; then konStates[kube-proxy]=$RUNNING; fi 
    fi
    
    # Sort view
    IFS=$'\n'
    keys=$(sort <<<"${!konStates[*]}")
    unset IFS

    pad=$(printf '%0.1s' " "{1..60})
    padlength=40
    bold=$(tput bold)
    normal=$(tput sgr0)
    header="true"
    
    # Print view
    for key in $keys
    do
        value=${konStates[$key]}
        if [ "$header" == "true" ]; then
            header1="Components"
            header2="State"
            if [ "$_arg_quiet" == "on" ]; then
                common::view_print "$padlength" "$pad" "$header1" "$header2"
            else
                common::view_print "$padlength" "$pad" "${bold}$header1" "$header2${normal}"
            fi
            common::view_print "$padlength" "$pad" "-----------------------" "----------"
        fi
        header="false"
        common::view_print "$padlength" "$pad" "$key" "$value"
    done
}

###############################################################################
# Updates kon to the latest and greatest version
###############################################################################
update () {
    info "updating ..."
    common::check_root

    # Remove old version
    rm -rf $KON_INSTALL_DIR
    docker rmi $(docker images -q thenatureofsoftware/kon) > $(common::dev_null) 2>&1

    # Trigger install of new version
    (KON_VERSION=latest kon --version > $(common::dev_null) 2>&1)

    info "kon updated to version: $(kon --version)"
}

# Move to stage 1 init funcion
#common::check_root
#common::mk_bindir

if [ "$1" == "install_script" ]; then
    kon::install_script
    if [ $? -gt 0 ]; then
        printf "%s\n" "error: failed to install script!"
        exit 1
    else
        printf "%s\n" "script installed successfully!"
        exit 0
    fi
fi

###############################################################################
# argbash
###############################################################################
parse_commandline "$@"
handle_passed_args_count
assign_positional_args

if [ $_arg_debug == on ]; then
    PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi
if [ $_arg_quiet == on ]; then NO_LOG=true; fi

###############################################################################
# Banner
###############################################################################
if [ "$_arg_quiet" == "off" ]; then
    consul_version="Consul not installed"
    nomad_version="Nomad not installed"
    kubernetes_version="kubelet not installed"
    kubeadm_version="kubeadm not installed"
    if [ "$(common::which consul)" ]; then consul_version="$(consul version|grep Consul)"; fi
    if [ "$(common::which nomad)" ]; then nomad_version="$(nomad version)"; fi
    if [ "$(common::which kubelet)" ]; then kubernetes_version="$(kubelet --version)"; fi
    if [ "$(common::which kubeadm)" ]; then kubeadm_version="kubeadm $(kubeadm version|awk -F':' '{ print $5 }'|awk -F',' '{print $1}'|sed 's/\"//g')"; fi
    cat $SCRIPTDIR/banner.txt
    echo "$(cat $SCRIPTDIR/version)"
    printf "$nomad_version, $consul_version, $kubernetes_version, $kubeadm_version\n\n"
fi

###############################################################################
# Check log file permissions
###############################################################################
touch $KON_LOG_FILE > $(common::dev_null) 2>&1 || KON_LOG_FILE="/tmp/kon.log"
touch $KON_LOG_FILE > $(common::dev_null) 2>&1 || KON_LOG_FILE="$(pwd)/kon.log"
touch $KON_LOG_FILE > $(common::dev_null) 2>&1 || KON_LOG_FILE=$(common::dev_null)

###############################################################################
# Load configuration
###############################################################################
config::configure
trap config::clean_up EXIT

###############################################################################
# Execute command                                                             #
###############################################################################
"$(echo ${_arg_command[*]} | sed 's/ /-/g')"
result=$?
if [ $result -eq 127 ]; then
    error "Command not found!"
    print_help
fi






