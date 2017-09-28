#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$BASEDIR/script
JOBDIR=$BASEDIR/nomad/job
K8S_ON_NOMAD_CONFIG_FILE=$BASEDIR/kubernetes_on_nomad.conf
K8S_CONFIGDIR=${K8S_PKIDIR:=/etc/kubernetes}
K8S_PKIDIR=${K8S_PKIDIR:=$K8S_CONFIGDIR/pki}


MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}
OBJECT_STORE="kube-store"
BUCKET="resources"
ETCD_SERVERS=${ETCD_SERVERS:=""}

###############################################################################
# Loads configuration file                                                    #
###############################################################################
kon::load_config () {
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
        rm -rf $K8S_PKIDIR/
    fi
    info "\n$(kubeadm alpha phase certs all --apiserver-advertise-address=$KUBE_APISERVER --apiserver-cert-extra-sans=$KUBE_APISERVER_EXTRA_SANS)"
    kon::put_cert_and_key "ca"
    kon::put_cert_and_key "apiserver"
    kon::put_cert_and_key "apiserver-kubelet-client"
    kon::put_cert_and_key "front-proxy-ca"
    kon::put_cert_and_key "front-proxy-client"
    consul::put_file kubernetes/certs/sa/key $K8S_PKIDIR/sa.key
    consul::put_file kubernetes/certs/sa/cert $K8S_PKIDIR/sa.pub
}

###############################################################################
# Generates kubeconfig files.                                                 #
###############################################################################
kon::generate_kubeconfigs () {
    IFS=',' read -ra MINIONS <<< "$KUBE_MINIONS"    
    for minion in ${MINIONS[@]}; do
        NAME=$(printf $minion|awk -F'=' '{print $1}')
        IP=$(printf $minion|awk -F'=' '{print $2}')
        kon::generate_kubeconfig "$NAME" "$IP"
    done
}

kon::generate_kubeconfig () {
    info "generating kubeconfig for minion: $1 with ip: $2"
    rm $K8S_CONFIGDIR/kubelet.conf > /dev/null 2>&1
    info "$(kubeadm alpha phase kubeconfig kubelet --node-name=$1 --apiserver-advertise-address=$KUBE_APISERVER --apiserver-bind-port=$KUBE_APISERVER_PORT)"
    info "$(kubectl --kubeconfig=/etc/kubernetes/kubelet.conf config set-cluster kubernetes --server=$KUBE_APISERVER_ADDRESS)"
    info "\n$(kubectl --kubeconfig=$K8S_CONFIGDIR/kubelet.conf config view)"
    info "\n$(consul::put_file kubernetes/minions/$1/kubeconfig $K8S_CONFIGDIR/kubelet.conf)"
    info "\n$(consul::put kubernetes/minions/$1/ip $2)"
}

kon::put_cert_and_key() {
    info "Storing key and cert for $1"
    consul::put_file kubernetes/certs/$1/key $K8S_PKIDIR/$1.key
    consul::put_file kubernetes/certs/$1/cert $K8S_PKIDIR/$1.crt
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

bootstrap::run_etcd () {
    
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

    info "Submitting job etcd to Nomad..."
    #info "$(nomad run ${JOBDIR}/etcd.nomad)"
    info "Job submited"

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

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/kon_common.sh
source $SCRIPTDIR/consul_install.sh

common::check_root
kon::load_config

#bootstrap::run_object_store
#log "Waiting for object store to start..."
#sleep 5
#log "Continuing ..."


#kon::generate_certificates
kon::generate_kubeconfigs

#bootstrap::run_etcd


