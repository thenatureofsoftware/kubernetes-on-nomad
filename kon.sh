#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Installation directory for all scripts.
KON_INSTALL_DIR=${KON_INSTALL_DIR:=/opt/kon}

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
minionKey="$kubernetesKey/minion"
controllerMgrKubeconfigKey="$kubernetesKey/controller-manager/kubeconfig"
schedulerKubeconfigKey="$kubernetesKey/scheduler/kubeconfig"
adminKubeconfigKey="$kubernetesKey/admin/kubeconfig"
minionsKey="$kubernetesKey/minions"
certsKey="$kubernetesKey/certs"
kubeProxyKey="$kubernetesKey/kube-proxy"
kubeProxyClusterCidrKey="$kubeProxyKey/cluster-cidr"
kubeProxyMasterKey="$kubeProxyKey/master"

etcdKey="etcd"
etcdServersKey="$etcdKey/servers"
etcdInitialClusterKey="$etcdKey/initial-cluster"
etcdInitialClusterTokenKey="$etcdKey/initial-cluster-token"

STOPPED="Stopped"
STARTED="Started"
RUNNING="Running"
CONFIGURED="Configured"
OK="OK"

###############################################################################
# Source                                                                      #
###############################################################################
source $SCRIPTDIR/arguments.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/config.sh
source $SCRIPTDIR/pki.sh
source $SCRIPTDIR/consul.sh
source $SCRIPTDIR/nomad.sh
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
# Generates certificates and stores them in consul
###############################################################################
kon::generate_certificates () {
    if [ ! "$(common::which kubeadm)" ]; then fail "kubeadm not installed, please install it first (kon kubernetes install)"; fi
    info "cleaning up any certificates in $K8S_PKI_DIR"
    if [ -d "$K8S_PKI_DIR" ]; then
        rm -rf $K8S_PKI_DIR/*
    else
        mkdir -p $K8S_PKI_DIR
    fi

    # Get any existing certificates from Consul
    kon::get_cert_and_key "ca"
    kon::get_cert_and_key "apiserver"
    kon::get_cert_and_key "apiserver-kubelet-client"
    kon::get_cert_and_key "front-proxy-ca"
    kon::get_cert_and_key "front-proxy-client"
    kon::get_cert_and_key "sa"

    # Call kubeadm to generate any missing certificates
    info "\n$(kubeadm alpha phase certs all --apiserver-advertise-address=$KUBE_APISERVER --apiserver-cert-extra-sans=$KUBE_APISERVER_EXTRA_SANS)"
    
    # Put all certificates back in Consul
    kon::put_cert_and_key "ca"
    kon::put_cert_and_key "apiserver"
    kon::put_cert_and_key "apiserver-kubelet-client"
    kon::put_cert_and_key "front-proxy-ca"
    kon::put_cert_and_key "front-proxy-client"
    kon::put_cert_and_key "sa"

    consul::put $certificateStateKey $OK
}

###############################################################################
# Generates kubeconfig files.
###############################################################################
kon::generate_kubeconfigs () {
        
    for minion in ${!config_minions[@]}; do
        minion_name=${config_minions[$minion]}
        minion_ip=$minion
        kon::generate_kubeconfig "$minion_name" "$minion_ip"
    done

    # kubeconfig for controller-manager
    info "$(kubeadm alpha phase kubeconfig controller-manager --cert-dir=$K8S_PKI_DIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for controller-manager"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for controller-manager"
    info "kubeconfig for controller-manager\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config view)"
    info "\n$(consul::put_file $controllerMgrKubeconfigKey $K8S_CONFIGDIR/controller-manager.conf)"

    # kubeconfig for scheduler
    info "$(kubeadm alpha phase kubeconfig scheduler --cert-dir=$K8S_PKI_DIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for scheduler"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for scheduler"
    info "kubeconfig for scheduler\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config view)"
    info "\n$(consul::put_file $schedulerKubeconfigKey $K8S_CONFIGDIR/scheduler.conf)"

    # kubeconfig for admin
    info "$(kubeadm alpha phase kubeconfig admin --cert-dir=$K8S_PKI_DIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for admin"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/admin.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for admin"
    info "kubeconfig for admin\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/admin.conf config view)"
    info "\n$(consul::put_file $adminKubeconfigKey $K8S_CONFIGDIR/admin.conf)"

    consul::put $kubeconfigStateKey $OK
}

###############################################################################
# Generates kubeconfig file for each node (minion).
###############################################################################
kon::generate_kubeconfig () {
    info "generating kubeconfig for minion: $1 with ip: $2"
    rm $K8S_CONFIGDIR/kubelet.conf > /dev/null 2>&1
    info "$(kubeadm alpha phase kubeconfig kubelet \
    --cert-dir=$K8S_PKI_DIR --node-name=$1 --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for minion: $1 with ip: $2"
    info "$(kubectl --kubeconfig=/etc/kubernetes/kubelet.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for minion: $1 with ip: $2"
    info "kubeconfig for $1:\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/kubelet.conf config view)"
    info "\n$(consul::put_file $minionsKey/$1/kubeconfig $K8S_CONFIGDIR/kubelet.conf)"
    info "\n$(consul::put $minionsKey/minions/$1/ip $2)"
}

###############################################################################
# Stores key and cert in consul given a key and cert pair name.
###############################################################################
kon::put_cert_and_key() {
    info "Storing key and cert for $1"
    consul::put_file $certsKey/$1/key $K8S_PKI_DIR/$1.key
    if [ "$1" == "sa" ]; then
        consul::put_file $certsKey/$1/cert $K8S_PKI_DIR/$1.pub
    else
        consul::put_file $certsKey/$1/cert $K8S_PKI_DIR/$1.crt
    fi
}

###############################################################################
# Fetches any existing cert and key from consul.
###############################################################################
kon::get_cert_and_key() {
    consul kv get $certsKey/$1/key > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        info "Found key and cert pair for $certsKey/$1"
        consul kv get $certsKey/$1/key > $K8S_PKI_DIR/$1.key
        if [ "$1" == "sa" ]; then
            consul kv get $certsKey/$1/cert > $K8S_PKI_DIR/$1.pub
        else
            consul kv get $certsKey/$1/cert > $K8S_PKI_DIR/$1.crt
        fi
    fi
}

###############################################################################
# Stopps and removes etcd.
###############################################################################
kon::reset_etcd () {
    nomad::stop_job "etcd"
    consul::delete_all $etcdKey
}

###############################################################################
# Validates etcd configuration and puts it in Consul.
###############################################################################
kon::load_etcd_config () {
    
    if [ "$ETCD_SERVERS" == "" ]; then
        error "ETCD_SERVERS is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER" == "" ]; then
        error "ETCD_INITIAL_CLUSTER is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER_TOKEN" == "" ]; then
        error "ETCD_INITIAL_CLUSTER_TOKEN is not set"
        exit 1
    fi

    # Put etcd configuration in Consul.
    consul::put $etcdServersKey "$ETCD_SERVERS"
    consul::put $etcdInitialClusterKey "$ETCD_INITIAL_CLUSTER"
    consul::put $etcdInitialClusterTokenKey "$ETCD_INITIAL_CLUSTER_TOKEN"

    currentState=$(consul::get $etcdStateKey)
    if [ ! "$currentState" == $STARTED ] && [ ! "$currentState" == $RUNNING ]; then
        consul::put $etcdStateKey $CONFIGURED
    fi
}

kon::load_kube_proxy_config () {
    if [ "$POD_CLUSTER_CIDR" == "" ]; then
        error "POD_CLUSTER_CIDR is not set"
        exit 1
    fi

    if [ "$KUBE_APISERVER_ADDRESS" == "" ]; then
        error "KUBE_APISERVER_ADDRESS is not set"
        exit 1
    fi

    consul::put $kubeProxyClusterCidrKey "$POD_CLUSTER_CIDR"
    consul::put $kubeProxyMasterKey "$KUBE_APISERVER_ADDRESS"

    consul::put $kubeProxyStateKey $OK
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
    nomad::install
    nomad::start
    kubernetes::install
}

###############################################################################
# Generates sample configuration file.
###############################################################################
generate-config () {
    if [ -f "$KON_CONFIG" ]; then
        fail "$KON_CONFIG already exists"
    fi
    config::generate_config_template
    info "you can now configure Kubernetes-On-Nomad by editing $KON_CONFIG"
}

###############################################################################
# Generates all kubernetes certificates.
###############################################################################
generate-certificates () {
    kon::generate_certificates
    common::fail_on_error "generating certificates failed"
}

###############################################################################
# Generates all kubeconfigs.
###############################################################################
generate-kubeconfigs () {
    
    if [ ! "$(consul::get $certificateStateKey)" == "generated" ]; then fail "certificates must be generated first"; fi

    # Verify and put configuration in Consul.
    kon::load_kube_proxy_config

    # Generate kubeconfigs.
    kon::generate_kubeconfigs
    common::fail_on_error "generating kubeconfigs failed"
}

###############################################################################
# Puts etcd configuration in Consul.
# The name doesn't reflect what we're doing, but makes sense from a user
# perspective.
###############################################################################
generate-etcd () {
    kon::load_etcd_config
}

generate-all () {
    kon::load_etcd_config
    kon::generate_certificates
    kon::generate_kubeconfigs
    kon::load_kube_proxy_config
}

reset-all () {
    kubernetes-reset
    kon::reset_etcd
}

reset-etcd () {
    kon::reset_etcd
}

start-all () {
  start-etcd
  sleep 5
  start-kubelet
  sleep 5
  start-kube-proxy
  sleep 5
  start-control-plane
}

###############################################################################
# Starts etcd 
###############################################################################
etcd-start () {

    for key in  $etcdServersKey $etcdInitialClusterKey $etcdInitialClusterTokenKey; do
        consul::fail_if_missing_key $key "$key is missing, generate etcd konfiguration first (generate etcd)"
    done
    
    info "starting etcd ..."
    nomad::run_job "etcd"
    info "etcd started"
}

###############################################################################
# Stops etcd 
###############################################################################
etcd-stop () {
    info "stopping etcd ..."
    nomad::stop_job "etcd"
    info "etcd stopped"
}

###############################################################################
# Starts kubelet 
###############################################################################
start-kubelet () {
    info "starting kubelet ..."
    nomad::run_job "kubelet"
    info "kubelet started"
}

###############################################################################
# Stop kubelet 
###############################################################################
stop-kubelet () {
    info "stopping kubelet ..."
    nomad::stop_job "kubelet"
    info "kubelet stopped"
}

###############################################################################
# Starts kube-proxy 
###############################################################################
start-kube-proxy () {
    info "starting kube-proxy ..."
    nomad::run_job "kube-proxy"
    info "kube-proxy started"
}

###############################################################################
# Stop kube-proxy 
###############################################################################
stop-kube-proxy () {
    info "stopping kube-proxy ..."
    nomad::stop_job "kube-proxy"
    info "kube-proxy stopped"
}

###############################################################################
# Starts the Kubernetes control plane 
###############################################################################
start-control-plane () {
    info "starting kubernetes control plane ..."
    for comp in kube-apiserver kube-scheduler kube-controller-manager; do
        nomad::run_job $comp
    done
    info "kubernetes control plane started"
}

###############################################################################
# Stops the Kubernetes control plane 
###############################################################################
stop-control-plane () {
    info "stopping kubernetes control plane ..."
    for comp in kube-apiserver kube-scheduler kube-controller-manager; do
        nomad::stop_job $comp
    done
    info "kubernetes control plane stopped"
}

addon-dns () {
    WORKDIR=/tmp/.kon 
    mkdir -p $WORKDIR
    KUBE_CONFIG=$WORKDIR/kubeconfig.conf
    consul kv get kubernetes/admin/kubeconfig > $WORKDIR/kubeconfig.conf
    kubeadm alpha phase addon kube-dns --kubeconfig=$KUBE_CONFIG  --kubernetes-version=$K8S_VERSION
}

setup-kubectl () {
    mkdir -p ~/.kube
    consul kv get kubernetes/admin/kubeconfig > ~/.kube/config
    if [ $? -eq 0 ]; then
        info "successfully configured kubectl"
    else
        error "failed to configure kubectl"
    fi
}

kubernetes-install () {
    kubernetes::install
}

kubernetes-reset () {
    kubernetes-stop
    consul::delete_all $kubernetesKey
    consul::put $certificateStateKey ""
    consul::put $kubeconfigStateKey ""
    rm -rf $K8S_PKI_DIR/*
    rm -rf $K8S_CONFIGDIR/*.*
}

kubernetes-start () {
    if [ ! "$(consul::get $certificateStateKey)" == $OK ]; then fail "certificates missing"; fi
    if [ ! "$(consul::get $kubeconfigStateKey)" == $OK ]; then fail "kubeconfig missing"; fi
    if [ ! "$(consul::get $etcdStateKey)" == "$STARTED" ] && [ ! "$(consul::get $etcdStateKey)" == "$RUNNIG" ]; then fail "etcd is not started"; fi
    start-control-plane
    start-kubelet
    start-kube-proxy
    consul::put $kubernetesStateKey $STARTED
}

kubernetes-stop () {
    stop-control-plane
    stop-kubelet
    stop-kube-proxy
    consul::put "kon/state/kubernetes" $STOPPED
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

cluster-start () {
    info "experimental command that starts the whole cluster"
    cluster::start
}

###############################################################################
# Shows the state of the cluster
###############################################################################
view-state () {
    # Default view
    declare -A konStates
    konStates=(
                [etcd]="" \
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

        # For each datacenter, check if it has any components running.
        for dc in "$(consul catalog datacenters)"; do

            if [ "$(dig +short "etcd.service.$dc.consul")" ]; then konStates[etcd]=$RUNNING; fi
            if [ "$(dig +short "controller-manager.service.$dc.consul")" ]; then konStates[kube-controller-manager]=$RUNNING; fi
            if [ "$(dig +short "scheduler.service.$dc.consul")" ]; then konStates[kube-scheduler]=$RUNNING; fi
            if [ "$(dig +short "kubernetes.service.$dc.consul")" ]; then
        
                # Kubernetes is running, now fetch the state of all minions.
                konStates[kubernetes]=$RUNNING
                konStates[kube-apiserver]=$RUNNING
                minions=$(kubectl get nodes -o json)
                for minion in $(echo $minions|jq '.items[].status.addresses[]|select(.type == "Hostname").address'|sed 's/"//g'); do
                    konStates[$minionKey/$minion]="$(kubectl get nodes -l "kubernetes.io/hostname=$minion" | sed '2q;d' | awk '{print $2}')"
                done
            fi
        done
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

    # Remove old version
    rm -rf $BASEDIR *

    # Trigger install of new version
    (KON_VERSION=latest kon --version > $(common::dev_null) 2>&1)

    info "kon updated to version: $(kon --version)"
}

# Move to stage 1 init funcion
#common::check_root
common::mk_bindir

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

###############################################################################
# Execute command                                                             #
###############################################################################
"$(echo ${_arg_command[*]} | sed 's/ /-/g')"
result=$?
if [ $result -eq 127 ]; then
    error "Command not found!"
    print_help
fi






