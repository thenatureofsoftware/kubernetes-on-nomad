#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Installation directory for all scripts.
KON_INSTALL_DIR=${INSTALL_DIR:=/etc/kon}

SCRIPTDIR=$BASEDIR/script
BINDIR=${BINDIR:=/opt/bin}
JOBDIR=$BASEDIR/nomad/job

KON_CONFIG=$KON_INSTALL_DIR/kon.conf
KON_LOG_FILE=/var/log/kon.log
K8S_CONFIGDIR=${K8S_CONFIGDIR:=/etc/kubernetes}
K8S_PKIDIR=${K8S_PKIDIR:=$K8S_CONFIGDIR/pki}

# Consul
CONSUL_VERSION=${CONSUL_VERSION:=0.9.3}

# Nomad
NOMAD_VERSION=${NOMAD_VERSION:=0.7.0-beta1}

MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}
OBJECT_STORE="kube-store"
BUCKET="resources"
ETCD_SERVERS=${ETCD_SERVERS:=""}

konKey="kon"
konConfig="$konKey/config"

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

STOPPED="stopped"
STARTED="started"
RUNNIG="running"
CONFIGURED="configured"
OK="OK"

###############################################################################
# Installs kon scripts                                                        #
###############################################################################
kon::install_script () {
    TARGET=$KON_INSTALL_DIR
    printf "%s\n" "Installing kubernetes-on-nomad to directory: $TARGET"
    if [ -d "$TARGET/script" ] || [ -f "$TARGET/kon.sh" ]; then
        printf "%s\n" "Error: target directory: $TARGET is not empty!"
        return 1
    fi
    
    mkdir -p $TARGET/script
    cp $SCRIPTDIR/* $TARGET/script
    
    mkdir -p $TARGET/nomad/job
    cp $JOBDIR/*.nomad $TARGET/nomad/job

    cp $BASEDIR/kon.sh $TARGET/

    chmod a+x $TARGET/script/*.sh
    chmod a+x $TARGET/kon.sh
}

###############################################################################
# Loads configuration file                                                    #
###############################################################################
kon::config () {
    mkdir -p $KON_INSTALL_DIR
    avtive_config=""
    
    if [ ! "$_arg_config" == "" ] && [ -f "$_arg_config" ]; then
        active_config=$_arg_config
    elif [ -f "$KON_CONFIG" ]; then
        active_config=$KON_CONFIG
    else
        consul::get $konConfig > $KON_CONFIG 2>&1
        if [ $? -eq 0 ]; then
            active_config=$KON_CONFIG
        else
            rm -f $KON_CONFIG
        fi
    fi

    if [ ! "$active_config" == "" ]; then
        info "loading configuration from $active_config"
        source $active_config
        if [ "$KON_SAMPLE_CONFIG" == "true" ]; then
            fail "can't use a sample configuration, please edit /etc/kon/kon.conf first"
        fi

        if [ -f "$KON_CONFIG" ]; then
            consul::put_file $konConfig $KON_CONFIG > "$(common::dev_null)" 2>&1
            if [ $? -eq 0 ]; then consul::put $configStateKey $OK; fi
        fi
    fi
}

###############################################################################
# Generates certificates and stores them in consul
###############################################################################
kon::generate_certificates () {
    if [ ! "$(common::which kubeadm)" ]; then fail "kubeadm not installed, please install it first (kon kubernetes install)"; fi
    info "cleaning up any certificates in $K8S_PKIDIR"
    if [ -d "$K8S_PKIDIR" ]; then
        rm -rf $K8S_PKIDIR/*
    else
        mkdir -p $K8S_PKIDIR
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

    rm $K8S_CONFIGDIR/*.conf /dev/null 2>&1
    IFS=',' read -ra MINIONS <<< "$KUBE_MINIONS"    
    for minion in ${MINIONS[@]}; do
        NAME=$(printf $minion|awk -F'=' '{print $1}')
        IP=$(printf $minion|awk -F'=' '{print $2}')
        kon::generate_kubeconfig "$NAME" "$IP"
    done

    # kubeconfig for controller-manager
    info "$(kubeadm alpha phase kubeconfig controller-manager --cert-dir=$K8S_PKIDIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for controller-manager"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for controller-manager"
    info "kubeconfig for controller-manager\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config view)"
    info "\n$(consul::put_file $controllerMgrKubeconfigKey $K8S_CONFIGDIR/controller-manager.conf)"

    # kubeconfig for scheduler
    info "$(kubeadm alpha phase kubeconfig scheduler --cert-dir=$K8S_PKIDIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    common::fail_on_error "failed to generate kubeconfig for scheduler"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    common::fail_on_error "failed to update apiserver address in kubeconfig for scheduler"
    info "kubeconfig for scheduler\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config view)"
    info "\n$(consul::put_file $schedulerKubeconfigKey $K8S_CONFIGDIR/scheduler.conf)"

    # kubeconfig for admin
    info "$(kubeadm alpha phase kubeconfig admin --cert-dir=$K8S_PKIDIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
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
    --cert-dir=$K8S_PKIDIR --node-name=$1 --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
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
    consul::put_file $certsKey/$1/key $K8S_PKIDIR/$1.key
    if [ "$1" == "sa" ]; then
        consul::put_file $certsKey/$1/cert $K8S_PKIDIR/$1.pub
    else
        consul::put_file $certsKey/$1/cert $K8S_PKIDIR/$1.crt
    fi
}

###############################################################################
# Fetches any existing cert and key from consul.
###############################################################################
kon::get_cert_and_key() {
    consul kv get $certsKey/$1/key > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        info "Found key and cert pair for $certsKey/$1"
        consul kv get $certsKey/$1/key > $K8S_PKIDIR/$1.key
        if [ "$1" == "sa" ]; then
            consul kv get $certsKey/$1/cert > $K8S_PKIDIR/$1.pub
        else
            consul kv get $certsKey/$1/cert > $K8S_PKIDIR/$1.crt
        fi
    fi
}

###############################################################################
# Stopps and removes etcd.
###############################################################################
kon::reset_etcd () {
    nomad::stop_job "etcd"
    info "$(consul kv delete -recurse $etcdKey)"
    info "$(consul kv delete $etcdStateKey)"
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
# Sets up the bootstrap node.
###############################################################################
setup-node-bootstrap () {
    consul::install
    consul-start-bootstrap
    nomad::install
    nomad::start
    kubernetes::install
}

###############################################################################
# Sets up an ordinary node.
###############################################################################
setup-node () {
    consul::install
    consul-start
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
    common::generate_config_template
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
    consul::delete $kubernetesKey
    consul::put $certificateStateKey "-"
    consul::put $kubeconfigStateKey "-"
}

kubernetes-start () {
    if [ ! "$(consul::get $certificateStateKey)" == "OK" ]; then fail "certificates missing"; fi
    if [ ! "$(consul::get $kubeconfigStateKey)" == "OK" ]; then fail "kubeconfig missing"; fi
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
        error "Please install Consul binaries first (kon install consul)"
        exit 1
    fi

    if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
        info "Bootstrap Consul is already running"
    else 
        consul::start-bootstrap
        common::fail_on_error "Failed to start consul"

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
        fail "Please install Consul binaries first (kon consul install)"
    fi
    
    if [ ! "$_arg_bootstrap" == "" ]; then
        KON_BOOTSTRAP_SERVER=$_arg_bootstrap
    fi

    if [ "$KON_BOOTSTRAP_SERVER" == "" ]; then
        error "Consul Bootstrap server address required. Please set KON_BOOTSTRAP_SERVER in config or --bootstrap <value> argument"
        exit 1
    fi
    info "Bootstrap server address: $KON_BOOTSTRAP_SERVER"

    if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
        info "Consul is already running"
    else 
        consul::start
        common::fail_on_error "Failed to start consul"

        consul::wait_for_started
    fi

    if [ ! -f "$KON_CONFIG" ]; then
        mkdir -p $KON_INSTALL_DIR
        
        kon_nameserver=$(consul kv get kon/nameserver)
        if [ $? -gt 0 ]; then fail "Failed to get nameserver from kon/nameserver"; fi

        info "Reading config from Consul"
        info "$(consul kv get kon/config > $KON_CONFIG)"

        if [ $? -eq 0 ] && [ -f "$KON_CONFIG" ]; then
            info "Reloading configuration from Consul."
            source $KON_CONFIG
            info "Restarting Consul after new configuration"
            
            consul::stop
            common::fail_on_error "Failed to stop consul"

            consul::start
            common::fail_on_error "Failed to start consul"

            consul::wait_for_started
        fi
    fi
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

view-state () {
    # Default view
    declare -A konStates
    konStates=(
                ["etcd"]="-" \
                ["consul"]="-" \
                ["config"]="-" \
                ["nomad"]="-" \
                ["certificates"]="-" \
                ["kubeconfig"]="-" \
                ["kubelet"]="-" \
                ["kube-proxy"]="-" \
                ["kube-apiserver"]="-" \
                ["kube-scheduler"]="-" \
                ["kube-controller-manager"]="-")

    if [ ! "$(dig +short "consul.service.dc1.consul")" == "" ]; then konStates["consul"]="running"; fi
    if [ ! "$(dig +short "nomad.service.dc1.consul")" == "" ]; then konStates["nomad"]="running"; fi

    # Fetch values for view
    if [ "${konStates["consul"]}" == "running" ]; then
        stateItems="$(consul kv get -recurse $stateKey)"
        for stateItem in $stateItems
        do
            key="$(echo $stateItem | awk -F '[/:]' '{print $3}')"
            value="$(echo $stateItem | awk -F '[:/]' '{print $4}')"
            konStates["$key"]="$value"
        done
    fi

    if [ ! "$(dig +short "etcd.service.dc1.consul")" == "" ]; then konStates["etcd"]="running"; fi
    if [ ! "$(dig +short "kubernetes.service.dc1.consul")" == "" ]; then
        konStates["kube-apiserver"]="running"
        konStates["kubernetes"]="running"
        minions=$(kubectl get nodes -o json)
        for minion in $(echo $minions|jq '.items[].status.addresses[]|select(.type == "Hostname").address'|sed 's/"//g'); do
            is_ready=$(echo $minions |jq 'select(.items[].status.addresses[].address == "core-01")|.items[].status.conditions[]|select(.type == "Ready")|.status' \
            | sed 's/"//g'|awk '{print tolower($0)}')
            if [ "$is_ready" == "true" ]; then
                value="ready";
            else
                value="not-ready"
            fi
            konStates["kubernetes/node/$minion"]="$value"
        done
    fi
    if [ ! "$(dig +short "controller-manager.service.dc1.consul")" == "" ]; then konStates["kube-controller-manager"]="running"; fi
    if [ ! "$(dig +short "scheduler.service.dc1.consul")" == "" ]; then konStates["kube-scheduler"]="running"; fi
    if [ "$(nomad job status -short kubelet|grep "^Status"|sed 's/ //g'|awk -F '=' '{print $2}')" == "running" ]; then konStates["kubelet"]="running"; fi
    if [ "$(nomad job status -short kube-proxy|grep "^Status"|sed 's/ //g'|awk -F '=' '{print $2}')" == "running" ]; then konStates["kube-proxy"]="running"; fi 
    
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
# Source                                                                      #
###############################################################################
source $SCRIPTDIR/arguments.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/kon_common.sh
source $SCRIPTDIR/consul.sh
source $SCRIPTDIR/nomad.sh
source $SCRIPTDIR/kubernetes.sh

# Move to stage 1 init funcion
common::check_root
common::mk_bindir

if [ "$1" == "install_script" ]; then
    kon::install_script
    if [ $? -gt 0 ]; then
        printf "%s\n" "Error: failed to install script!"
        exit 1
    else
        printf "%s\n" "Script installed successfully!"
        exit 0
    fi
fi

###############################################################################
# argbash
###############################################################################
parse_commandline "$@"
handle_passed_args_count
assign_positional_args

if [ $_arg_debug == on ]; then set -x; fi
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
    printf "$nomad_version, $consul_version, $kubernetes_version, $kubeadm_version\n\n"
fi

###############################################################################
# Load configuration                                                          #
###############################################################################
kon::config

###############################################################################
# Execute command                                                             #
###############################################################################
"$(echo ${_arg_command[*]} | sed 's/ /-/g')"
result=$?
if [ $result -eq 127 ]; then
    error "Command not found!"
    print_help
fi






