#!/bin/bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$BASEDIR/script
JOBDIR=$BASEDIR/nomad/job
BOOTSTRAP_K8S_CONFIG_FILE=$BASEDIR/kubernetes_bootstrap_config.env
BOOTSTRAP_K8S_CONFIG_BUNDLE_FILE_NAME=kubernetes_config.tar.gz
BOOTSTRAP_K8S_CONFIG_BUNDLE=$BASEDIR/$BOOTSTRAP_K8S_CONFIG_BUNDLE_FILE_NAME
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}
OBJECT_STORE="kube-store"
BUCKET="resources"
ETCD_SERVERS=${ETCD_SERVERS:=""}

bootstrap::env_file () {
    if [ -f /tmp/setup.env ]; then
        log "Loading environment variables from /tmp/setup.env"
        source /tmp/setup.env
    fi
    if [ -f $BASEDIR/setup.env ]; then
        log "Loading environment variables from $BASEDIR/setup.env"
        source $BASEDIR/setup.env
    fi
    log "etcd servers: $ETCD_SERVERS"
    log "etcd initial-cluster: $ETCD_INITIAL_CLUSTER"
    log "etcd initial-cluster-token: $ETCD_INITIAL_CLUSTER_TOKEN"
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
    log "Submitting job etcd to Nomad..."
    log "$(nomad run ${JOBDIR}/etcd.nomad)"
    log "Job submited"
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
source $SCRIPTDIR/consul_install.sh

common::check_root
bootstrap::env_file

#bootstrap::run_object_store
#log "Waiting for object store to start..."
#sleep 5
#log "Continuing ..."

consul::put "etcd/servers" "$ETCD_SERVERS"
consul::put "etcd/initial-cluster" "$ETCD_INITIAL_CLUSTER"
consul::put "etcd/initial-cluster-token" "$ETCD_INITIAL_CLUSTER_TOKEN"

#bootstrap::create_k8s_config
#source $BOOTSTRAP_K8S_CONFIG_FILE
#bootstrap::upload_bundle
#BOOTSTRAP_K8S_CONFIG_BUNDLE=$(sudo mc share download kube-store/resources/kubernetes_config.tar.gz|grep Share)
#consul::put "kubernetes/config-bundle" "${BOOTSTRAP_K8S_CONFIG_BUNDLE:7}"
#consul::put "kubernetes/join-token" "$KUBEADM_JOIN_TOKEN"

bootstrap::run_etcd
#bootstrap::run_kubelet
#bootstrap::run_kube-control-plane

source $BOOTSTRAP_K8S_CONFIG_FILE

