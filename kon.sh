#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$BASEDIR/script
BINDIR=${BINDIR:=/usr/bin}

JOBDIR=$BASEDIR/nomad/job
K8S_ON_NOMAD_CONFIG_FILE=$BASEDIR/kon.conf
KON_LOG_FILE=$BASEDIR/kon.log
K8S_CONFIGDIR=${K8S_CONFIGDIR:=/etc/kubernetes}
K8S_PKIDIR=${K8S_PKIDIR:=$K8S_CONFIGDIR/pki}


MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}
OBJECT_STORE="kube-store"
BUCKET="resources"
ETCD_SERVERS=${ETCD_SERVERS:=""}

###############################################################################
# Checks that the script is run as root                                       #
###############################################################################
kon::check_root () {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root"
        exit 1
    fi
}

###############################################################################
# Loads configuration file                                                    #
###############################################################################
kon::conf () {
    if [ ! -f "$K8S_ON_NOMAD_CONFIG_FILE" ]; then
        err "$K8S_ON_NOMAD_CONFIG_FILE no such file"
        kon::generate_config_template
        exit 1
    fi
    source $K8S_ON_NOMAD_CONFIG_FILE
}

###############################################################################
# Generates certificates and stores them in consul.                           #
###############################################################################
kon::generate_certificates () {
    info "Cleaning up any certificates in $K8S_PKIDIR"
    if [ -d "$K8S_PKIDIR" ]; then
        rm -rf $K8S_PKIDIR/*
    else
        mkdir -p $K8S_PKIDIR
    fi
    kon::get_cert_and_key "ca"
    kon::get_cert_and_key "apiserver"
    kon::get_cert_and_key "apiserver-kubelet-client"
    kon::get_cert_and_key "front-proxy-ca"
    kon::get_cert_and_key "front-proxy-client"
    kon::get_cert_and_key "sa"

    info "\n$(kubeadm alpha phase certs all --apiserver-advertise-address=$KUBE_APISERVER --apiserver-cert-extra-sans=$KUBE_APISERVER_EXTRA_SANS)"
    kon::put_cert_and_key "ca"
    kon::put_cert_and_key "apiserver"
    kon::put_cert_and_key "apiserver-kubelet-client"
    kon::put_cert_and_key "front-proxy-ca"
    kon::put_cert_and_key "front-proxy-client"
    kon::put_cert_and_key "sa"
}

###############################################################################
# Generates kubeconfig files.                                                 #
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
# Generates kubeconfig file for each node (minion).                           #
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
# Stores key and cert in consul given a key and cert pair name.               #
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
# Fetches any existing cert and key from consul                               #
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
# Stopps and removes etcd                                                     #
###############################################################################
kon::reset_etcd () {
    info "$(nomad stop etcd)"
    info "$(consul kv delete -recurse etcd)"
}

###############################################################################
# Stopps and removes kubernetes                                               #
###############################################################################
kon::reset_kubernetes () {
    info "$(nomad stop kube-control-plane)"
    info "$(nomad stop kubelet)"
    info "$(consul kv delete -recurse kubernetes)"
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

kon::load_etcd_config () {
    
    if [ "$ETCD_SERVERS" == "" ]; then
        err "ETCD_SERVERS is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER" == "" ]; then
        err "ETCD_INITIAL_CLUSTER is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER_TOKEN" == "" ]; then
        err "ETCD_INITIAL_CLUSTER_TOKEN is not set"
        exit 1
    fi

    consul::put "etcd/servers" "$ETCD_SERVERS"
    consul::put "etcd/initial-cluster" "$ETCD_INITIAL_CLUSTER"
    consul::put "etcd/initial-cluster-token" "$ETCD_INITIAL_CLUSTER_TOKEN"
}

kon::load_kube_proxy_config () {
    if [ "$POD_CLUSTER_CIDR" == "" ]; then
        err "POD_CLUSTER_CIDR is not set"
        exit 1
    fi

    if [ "$KUBE_APISERVER_ADDRESS" == "" ]; then
        err "KUBE_APISERVER_ADDRESS is not set"
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
# Commands                                                                    #
###############################################################################
enable-dns () {
    consul::enable_dns
}

generate-certificates () {
    kon::generate_certificates
}

generate-kubeconfigs () {
    kon::load_kube_proxy_config
    kon::generate_kubeconfigs
}

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

reset-kubernetes () {
    kon::reset_kubernetes
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

start-etcd () {
    info "Starting etcd ..."
    info "$(nomad run $JOBDIR/etcd.nomad)"
    sleep 5
    info "etcd job status after 5 sec:\n$(nomad job status etcd)"
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
        err "Failed to configure kubectl"
    fi
}

install-kube () {
    kubelet::install
}

###############################################################################
# Show help                                                                   #
###############################################################################
kon::help () {
    cat <<EOF
    
KON helps you setup and run Kubernetes On Nomad.

Install Commands:
  install kube             Installs kubernetes components: kubelet, kubeadm and kubectl

Generate Commands:
  generate all             Generates certificates and kubeconfigs.
  generate etcd            Reads the etcd configuration and stores it in consul.
  generate certificates    Generates all certificates and stores them in consul. The command only generates missing certificates and is safe to be run multiple times.
  generate kubeconfigs     Generates all kubeconfig-files and stores them in consul.

Start Commands:
  start all
  start etcd
  start kubelet
  start kube-proxy
  start control-plane

Reset Commands:
  reset all                Stopps all running jobs and deletes all certificates and configuration.
  reset etcd               Stopps etcd and deletes all configuration.
  reset kubernetes         Stopps kubernetes control plane and deletes all certificates and configuration.
  

Other Commands:
  enable dns               Enables service lookup in consul using the hosts resolv.conf.
  addon dns                Installs dns addon.
  setup kubectl            Configures kubectl for accessing the cluster.

EOF
}

###############################################################################
# Source                                                                      #
###############################################################################
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/kon_common.sh
source $SCRIPTDIR/consul_install.sh
source $SCRIPTDIR/kubelet_install.sh

###############################################################################
# Check root and load kon.conf                                                               #
###############################################################################
kon::check_root
kon::conf

###############################################################################
# Display banner                                                              #
###############################################################################
cat $SCRIPTDIR/banner.txt
printf "$(nomad version), $(consul version|grep Consul), Kubernetes $K8S_VERSION, kubeadm $KUBEADM_VERSION\n\n"

###############################################################################
# Execute command                                                             #
###############################################################################
if [ "_$1" = "_" ]; then
    kon::help
else
    if [ '$(kon::help|grep "${@})"' == '' ]; then
        kon::help
    else
        "$(echo $@ | sed 's/ /-/g')"
        result=$?
        if [ $result -eq 127 ]; then
            err "Command not found!"
            kon::help
        fi
    fi
fi



