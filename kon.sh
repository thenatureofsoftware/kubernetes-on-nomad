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
# Checks that the script is run as root                                       #
###############################################################################
kon::check_root () {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
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
    fi

    if [ ! "$active_config" == "" ]; then
        info "Loading configuration from $active_config"
        source $active_config
        if [ "$KON_SAMPLE_CONFIG" == "true" ]; then
            fail "Can't use a sample configuration, please edit /etc/kon/kon.conf"
        fi
    fi
}

###############################################################################
# Generates certificates and stores them in consul
###############################################################################
kon::generate_certificates () {
    if [ ! "$(common::which kubeadm)" ]; then fail "kubeadm not installed, please install it first (kon kubernetes install)"; fi
    info "Cleaning up any certificates in $K8S_PKIDIR"
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
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    info "kubeconfig for controller-manager\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/controller-manager.conf config view)"
    info "\n$(consul::put_file kubernetes/controller-manager/kubeconfig $K8S_CONFIGDIR/controller-manager.conf)"

    # kubeconfig for scheduler
    info "$(kubeadm alpha phase kubeconfig scheduler --cert-dir=$K8S_PKIDIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    info "kubeconfig for scheduler\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/scheduler.conf config view)"
    info "\n$(consul::put_file kubernetes/scheduler/kubeconfig $K8S_CONFIGDIR/scheduler.conf)"

    # kubeconfig for admin
    info "$(kubeadm alpha phase kubeconfig admin --cert-dir=$K8S_PKIDIR --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    info "$(kubectl --kubeconfig=$K8S_CONFIGDIR/admin.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    info "kubeconfig for admin\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/admin.conf config view)"
    info "\n$(consul::put_file kubernetes/admin/kubeconfig $K8S_CONFIGDIR/admin.conf)"
}

###############################################################################
# Generates kubeconfig file for each node (minion).
###############################################################################
kon::generate_kubeconfig () {
    info "generating kubeconfig for minion: $1 with ip: $2"
    rm $K8S_CONFIGDIR/kubelet.conf > /dev/null 2>&1
    info "$(kubeadm alpha phase kubeconfig kubelet \
    --cert-dir=$K8S_PKIDIR --node-name=$1 --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    info "$(kubectl --kubeconfig=/etc/kubernetes/kubelet.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    info "kubeconfig for $1:\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/kubelet.conf config view)"
    info "\n$(consul::put_file kubernetes/minions/$1/kubeconfig $K8S_CONFIGDIR/kubelet.conf)"
    info "\n$(consul::put kubernetes/minions/$1/ip $2)"
}

###############################################################################
# Stores key and cert in consul given a key and cert pair name.
###############################################################################
kon::put_cert_and_key() {
    info "Storing key and cert for $1"
    consul::put_file kubernetes/certs/$1/key $K8S_PKIDIR/$1.key
    if [ "$1" == "sa" ]; then
        consul::put_file kubernetes/certs/$1/cert $K8S_PKIDIR/$1.pub
    else
        consul::put_file kubernetes/certs/$1/cert $K8S_PKIDIR/$1.crt
    fi
}

###############################################################################
# Fetches any existing cert and key from consul.
###############################################################################
kon::get_cert_and_key() {
    consul kv get kubernetes/certs/$1/key > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        info "Found key and cert pair for kubernetes/certs/$1"
        consul kv get kubernetes/certs/$1/key > $K8S_PKIDIR/$1.key
        if [ "$1" == "sa" ]; then
            consul kv get kubernetes/certs/$1/cert > $K8S_PKIDIR/$1.pub
        else
            consul kv get kubernetes/certs/$1/cert > $K8S_PKIDIR/$1.crt
        fi
    fi
}

###############################################################################
# Stopps and removes etcd.
###############################################################################
kon::reset_etcd () {
    info "$(nomad stop etcd)"
    info "$(consul kv delete -recurse etcd)"
}

bootstrap::run_object_store () {
    log "Starting object store in nomad..."
    sed -e "s/\${MINIO_ACCESS_KEY}/${MINIO_ACCESS_KEY}/g" -e "s/\${MINIO_SECRET_KEY}/${MINIO_SECRET_KEY}/g" "${JOBDIR}/minio.nomad" | nomad run -
    nomad job status minio
    log "Object store started"
}

bootstrap::create_k8s_config () {
    bootstrap::reset_k8s
    if [ ! -f $BOOTSTRAP_K8S_CONFIG_BUNDLE ]; then
        bootstrap::reset_k8s
        
        bootstrap::generate_token
        log "Kubernetes join-token: $KUBEADM_JOIN_TOKEN"

        kubeadm init --token $KUBEADM_JOIN_TOKEN --apiserver-cert-extra-sans=kubernetes.service.dc1.consul
        
        # rm /etc/kubernetes/manifests/*
        tar zcf $BOOTSTRAP_K8S_CONFIG_BUNDLE -C /etc/kubernetes ./
        
        bootstrap::reset_k8s
    else
        log "Kubernetes config bundle already exists, skipping"
    fi
    common::rm_all_running_containers
}

bootstrap::reset_k8s () {
    kubeadm reset
    log "Stopping kubelet.service"
    systemctl stop kubelet
    log "Disable kubelet.service"
    systemctl disable kubelet
    common::rm_all_running_containers
    rm -rf /var/lib/kubelet/*
}

bootstrap::generate_token () {
    KUBEADM_JOIN_TOKEN=$(kubeadm token generate)
    cat <<EOF > $BOOTSTRAP_K8S_CONFIG_FILE
#!/bin/bash
KUBEADM_JOIN_TOKEN=${KUBEADM_JOIN_TOKEN}

EOF
}

bootstrap::upload_bundle () {
    MINIO_URL="http://$(common::service_address http://localhost:8500/v1/catalog/service/minio)"
    log "Uploading config bundle to ${MINIO_URL}"
    mc config host add $OBJECT_STORE $MINIO_URL $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
    mc -q mb $OBJECT_STORE/$BUCKET
    mc -q cp $BOOTSTRAP_K8S_CONFIG_BUNDLE $OBJECT_STORE/$BUCKET
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
    consul::put "etcd/servers" "$ETCD_SERVERS"
    consul::put "etcd/initial-cluster" "$ETCD_INITIAL_CLUSTER"
    consul::put "etcd/initial-cluster-token" "$ETCD_INITIAL_CLUSTER_TOKEN"
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

    consul::put "kubernetes/kube-proxy/cluster-cidr" "$POD_CLUSTER_CIDR"
    consul::put "kubernetes/kube-proxy/master" "$KUBE_APISERVER_ADDRESS"
}

bootstrap::run_kubelet () {
    log "Submitting job kubelet to Nomad..."
    BOOTSTRAP_K8S_CONFIG_BUNDLE=$(consul kv get kubernetes/config-bundle)
    export BOOTSTRAP_K8S_CONFIG_BUNDLE=$(consul kv get kubernetes/config-bundle); cat ${JOBDIR}/kubelet.nomad | envsubst '$BOOTSTRAP_K8S_CONFIG_BUNDLE' | nomad run -
    log "Job submited"
}

bootstrap::run_kube-control-plane () {
    log "Submitting job kube-control-plane to Nomad..."
    BOOTSTRAP_K8S_CONFIG_BUNDLE=$(consul kv get kubernetes/config-bundle)
    export BOOTSTRAP_K8S_CONFIG_BUNDLE=$(consul kv get kubernetes/config-bundle); cat ${JOBDIR}/kube-control-plane.nomad | envsubst '$BOOTSTRAP_K8S_CONFIG_BUNDLE' | nomad run -
    log "Job submited"
}

###############################################################################
# Commands:
# generate-config - Generates sample configuration file.
# generate-certificates - Generates all kubernetes certificates.
# generate-kubeconfigs - Generates all kubeconfigs.
###############################################################################


###############################################################################
# Generates sample configuration file.
###############################################################################
generate-config () {
    if [ -f "$KON_CONFIG" ]; then
        fail "$KON_CONFIG already exists"
    fi
    common::generate_config_template
    info "You can now configure Kubernetes-On-Nomad by editing $KON_CONFIG"
}

###############################################################################
# Generates all kubernetes certificates.
###############################################################################
generate-certificates () {
    kon::generate_certificates
}

###############################################################################
# Generates all kubeconfigs.
###############################################################################
generate-kubeconfigs () {
    # Verify and put configuration in Consul.
    kon::load_kube_proxy_config
    # Generate kubeconfigs.
    kon::generate_kubeconfigs
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
    kon::reset_kubernetes
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

etcd-start () {
    nomad::check
    info "Starting etcd ..."
    info "$(nomad run $JOBDIR/etcd.nomad)"
    common::error_on_error "etcd start failed"
    sleep 5
    info "etcd job status after 5 sec:\n$(nomad job status etcd)"
}

etcd-stop () {
    nomad::check
    info "Stopping etcd ..."
    info "$(nomad stop -purge etcd)"
    common::error_on_error "etcd stop failed"
}

start-kubelet () {
    info "Starting kubelet ..."
    info "$(nomad run $JOBDIR/kubelet.nomad)"
    sleep 5
    info "kubelet job status after 5 sec:\n$(nomad job status kubelet)"
}

start-kube-proxy () {
    info "Starting kube-proxy ..."
    info "$(nomad run $JOBDIR/kube-proxy.nomad)"
    sleep 5
    info "kube-proxy job status after 5 sec:\n$(nomad job status kube-proxy)"
}

start-control-plane () {
    info "Starting kubernetes control plane ..."
    info "$(nomad run $JOBDIR/kube-control-plane.nomad)"
    sleep 5
    info "Kubernetes control plane job status after 5 sec:\n$(nomad job status kube-control-plane)"
}

addon-kube-proxy () {
    
    WORKDIR=/tmp/.kon 
    mkdir -p $WORKDIR
    KUBE_CONFIG=$WORKDIR/kubeconfig.conf
    consul kv get kubernetes/admin/kubeconfig > $WORKDIR/kubeconfig.conf
    kubeadm alpha phase addon kube-proxy --kubeconfig=$KUBE_CONFIG --kubernetes-version=$K8S_VERSION --pod-network-cidr=10.244.0.0/16
    kubectl -n kube-system get cm kube-proxy -o json|jq --raw-output '.data["kubeconfig.conf"]' > $WORKDIR/kubeconfig.conf
    info "$(kubectl --kubeconfig=$WORKDIR/kubeconfig.conf config set-cluster default --server=$KUBE_APISERVER_ADDRESS)"
    kubectl -n kube-system delete cm kube-proxy
    kubectl -n kube-system create cm kube-proxy --from-file=$WORKDIR/kubeconfig.conf
    kubectl -n kube-system delete pods -l k8s-app=kube-proxy
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.8.0/Documentation/kube-flannel.yml
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.8.0/Documentation/kube-flannel-rbac.yml
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
        info "Successfully configured kubectl"
    else
        error "Failed to configure kubectl"
    fi
}

kubernetes-install () {
    kubernetes::install
}

kubernetes-reset () {
    kubernetes::reset
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
kon::check_root
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

###############################################################################
# argbash
###############################################################################
parse_commandline "$@"
handle_passed_args_count
assign_positional_args

if [ $_arg_debug == on ]; then set -x; fi

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






