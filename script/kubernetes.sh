#!/bin/bash

###############################################################################
# Installs all Kubernetes components
###############################################################################
kubernetes::install () {
    info "installing Kubernetes components ..."
    kubernetes::install_by_download
    info "done installing Kubernetes components"
}

###############################################################################
# Installs by download
###############################################################################
kubernetes::install_by_download () {

    mkdir -p /etc/kubernetes/manifests
    for kube_component in kubeadm kubectl kubelet kube-apiserver kube-scheduler kube-controller-manager; do
        if [ ! $(common::which $kube_component) ]; then
            
            local version=""
            if [ "$kube_component" == "kubeadm" ]; then
                version=$KUBEADM_VERSION
            else
                version=$K8S_VERSION
            fi

            kubernetes::download_and_install "$kube_component" "$version"
            common::fail_on_error "failed to install $kube_component"
        else
            info "$kube_component already installed"
        fi
    done

    
    if [ ! -f "/opt/cni/bin/loopback" ]; then
        if [ "$CNI_VERSION" == "" ]; then fail "CNI_VERSION is not set, is KON_CONFIG loaded?"; fi
        info "installing cni plugins..."
        info "$CNI_VERSION"
        mkdir -p /opt/cni/bin
        curl -sL https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-amd64-$CNI_VERSION.tgz | tar zxv -C /opt/cni/bin > "$(common::dev_null)" 2>&1
        common::fail_on_error "failed to install cni plugins"
    else
        info "cni plugins already installed"
    fi
}

###############################################################################
# Installs by using package manager
###############################################################################
kubernetes::install_by_apt () {
    apt-get update > "$(common::dev_null)" 2>&1
    apt-get install -y apt-transport-https > "$(common::dev_null)" 2>&1
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - > "$(common::dev_null)" 2>&1
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    local k8s_version=$(echo $K8S_VERSION | sed 's/v//g')-00
    apt-get update > "$(common::dev_null)" 2>&1
    apt-get install -y kubelet=$k8s_version kube-apiserver=$k8s_version > "$(common::dev_null)" 2>&1
    kubelet::reset
}

###############################################################################
# Download helper function
###############################################################################
kubernetes::download_and_install() {
    if [ "$1" == "" ] || [ "$2" == "" ]; then
        fail "both component and version is required, got component:$2 and version:$1"
    fi

    info "downloading and installing: $1 version: $2"
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$2/bin/linux/amd64/$1
    chmod a+x $1
    mv $1 $BINDIR
    info "done installing $1"
}

###############################################################################
# Configures all Kubernetes components (certificates and kubeconfig).
###############################################################################
kubernetes::config () {

    for key in $kubeProxyClusterCidrKey $certsKey/apiserver/cert $certsKey/apiserver/key $adminKubeconfigKey $schedulerKubeconfigKey $controllerMgrKubeconfigKey; do
        if [ "$(consul::has_key $key)" ]; then
            fail "kubernetes is already configured, please reset first";
        fi    
    done

    kubernetes::generate_certificates
    kubernetes::generate_kubeconfigs
    kubernetes::load_kube_proxy_config

    # Setup kubectl
    mkdir -p ~/.kube
    consul kv get kubernetes/admin/kubeconfig > ~/.kube/config
    if [ $? -eq 0 ]; then
        info "successfully configured kubectl"
    else
        error "failed to configure kubectl"
    fi
}

###############################################################################
# Generates certificates and stores them in consul
###############################################################################
kubernetes::generate_certificates () {
    # If the certificates isn't ready then run setup
    if [ ! -f "$KON_PKI_DIR/ca.key" ]; then pki::setup_node_certificates; fi

    if [ ! "$(common::which kubeadm)" ]; then fail "kubeadm not installed, please install it first (kon kubernetes install)"; fi
    info "cleaning up any certificates in $K8S_PKI_DIR"
    if [ -d "$K8S_PKI_DIR" ]; then
        rm -rf $K8S_PKI_DIR/*
    else
        mkdir -p $K8S_PKI_DIR
    fi
    # Use the KON CA for generating certificates for Kubernetes
    ln -s $KON_PKI_DIR/ca.crt $K8S_PKI_DIR/ca.crt
    ln -s $KON_PKI_DIR/ca.key $K8S_PKI_DIR/ca.key

    # Get any existing certificates from Consul
    kubernetes::get_cert_and_key "apiserver"
    kubernetes::get_cert_and_key "apiserver-kubelet-client"
    kubernetes::get_cert_and_key "front-proxy-ca"
    kubernetes::get_cert_and_key "front-proxy-client"
    kubernetes::get_cert_and_key "sa"

    # Call kubeadm to generate any missing certificates
    info "\n$(kubeadm alpha phase certs all --apiserver-advertise-address=$KUBE_APISERVER --apiserver-cert-extra-sans=$KUBE_APISERVER_EXTRA_SANS)"
    
    # Put all certificates back in Consul
    kubernetes::put_cert_and_key "apiserver"
    kubernetes::put_cert_and_key "apiserver-kubelet-client"
    kubernetes::put_cert_and_key "front-proxy-ca"
    kubernetes::put_cert_and_key "front-proxy-client"
    kubernetes::put_cert_and_key "sa"

    consul::put $certificateStateKey $OK
}

###############################################################################
# Generates kubeconfig files.
###############################################################################
kubernetes::generate_kubeconfigs () {
        
    for minion in ${!config_minions[@]}; do
        minion_name=${config_minions[$minion]}
        minion_ip=$minion
        kubernetes::generate_kubeconfig "$minion_name" "$minion_ip"
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
kubernetes::generate_kubeconfig () {
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
kubernetes::put_cert_and_key() {
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
kubernetes::get_cert_and_key() {
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
# Configures and starts Kubernetes networking
###############################################################################
kubernetes::start-network () {

    # Verify apiserver is up and running
    for (( ;; )); do
        sleep 10
        info "waiting for apiserver to start..."
        if [ "$(dig +short kubernetes.service.consul)" ]; then
            info "kubernetes apiserver is running!"
            break;
        fi 
    done

    if [ "$(consul::has_key $kubernetesNetworkKey)" ]; then
        info "kubernetes network already configured"
        kubernetes::start-kube-proxy
        return $?
    fi

    if [ ! "$KON_POD_NETWORK" ]; then fail "KON_POD_NETWORK is missing, is KON_CONFIG loaded?"; fi

    # Install and start Pod networking
    case "$KON_POD_NETWORK" in
        weave)
            info "installing Weave Net"
            kubernetes::start-kube-proxy
            kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
            ;;
        flannel)
            info "installing flannel"
            kubernetes::start-kube-proxy
            kubectl apply -f "https://raw.githubusercontent.com/coreos/flannel/v0.9.0/Documentation/kube-flannel.yml"
            ;;
        calico)
            info "installing calico"
            kubernetes::start-kube-proxy
            kubectl apply -f "kubectl apply -f https://docs.projectcalico.org/v2.6/getting-started/kubernetes/installation/hosted/kubeadm/1.6/calico.yaml"
            ;;
        *)
            fail "unknown pod network: $KON_POD_NETWORK"
            ;;
    esac

    # Install Kubernetes DNS
    WORKDIR=/tmp/.kon 
    mkdir -p $WORKDIR
    KUBE_CONFIG=$WORKDIR/kubeconfig.conf
    consul kv get kubernetes/admin/kubeconfig > $KUBE_CONFIG
    kubeadm alpha phase addon kube-dns --kubeconfig=$KUBE_CONFIG  --kubernetes-version=$K8S_VERSION
    
    consul::put $kubernetesNetworkKey "$KON_POD_NETWORK"
    consul::put $kubeProxyStateKey $OK
}

kubernetes::reset () {
    kubernetes::stop
    consul::delete_all $kubernetesKey
    consul::put $certificateStateKey "$NOT_CONFIGURED"
    consul::put $kubeconfigStateKey "$NOT_CONFIGURED"
    rm -rf $K8S_PKI_DIR/*
    rm -rf $K8S_CONFIGDIR/*.*
}

kubernetes::start () {
    if [ ! "$(consul::get $certificateStateKey)" == $OK ]; then fail "certificates missing"; fi
    if [ ! "$(consul::get $kubeconfigStateKey)" == $OK ]; then fail "kubeconfig missing"; fi
    if [ ! "$(consul::get $etcdStateKey)" == "$STARTED" ] && [ ! "$(consul::get $etcdStateKey)" == "$RUNNIG" ]; then fail "etcd is not started"; fi
    kubernetes::start-control-plane
    kubernetes::start-kubelet
    kubernetes::start-network
    consul::put $kubernetesStateKey $STARTED
}

kubernetes::stop () {
    kubernetes::stop-control-plane
    kubernetes::stop-kubelet
    kubernetes::stop-kube-proxy
    consul::put "kon/state/kubernetes" $STOPPED
}

###############################################################################
# Starts kubelet 
###############################################################################
kubernetes::start-kubelet () {
    info "starting kubelet ..."
    nomad::run_job "kubelet"
    info "kubelet started"
}

###############################################################################
# Stop kubelet 
###############################################################################
kubernetes::stop-kubelet () {
    info "stopping kubelet ..."
    nomad::stop_job "kubelet"
    info "kubelet stopped"
}

###############################################################################
# Starts kube-proxy 
###############################################################################
kubernetes::start-kube-proxy () {
    info "starting kube-proxy ..."
    nomad::run_job "kube-proxy"
    info "kube-proxy started"
}

###############################################################################
# Stop kube-proxy 
###############################################################################
kubernetes::stop-kube-proxy () {
    info "stopping kube-proxy ..."
    nomad::stop_job "kube-proxy"
    info "kube-proxy stopped"
}

###############################################################################
# Starts the Kubernetes control plane 
###############################################################################
kubernetes::start-control-plane () {
    
    # Install and start Pod networking
    if [ ! "$KON_POD_NETWORK" ]; then fail "KON_POD_NETWORK is missing, is KON_CONFIG loaded?"; fi
    case "$KON_POD_NETWORK" in
        weave)
            consul::put $kubernetesPodNetworkCidrKey "10.32.0.0/16"
            ;;
        flannel)
            consul::put $kubernetesPodNetworkCidrKey "10.244.0.0/16"
            ;;
        calico)
            consul::put $kubernetesPodNetworkCidrKey "192.168.0.0/16"
            ;;
        *)
            fail "unknown pod network: $KON_POD_NETWORK"
            ;;
    esac

    info "starting kubernetes control plane ..."
    for comp in kube-apiserver kube-scheduler kube-controller-manager; do
        nomad::run_job $comp
    done
    info "kubernetes control plane started"
}

###############################################################################
# Stops the Kubernetes control plane 
###############################################################################
kubernetes::stop-control-plane () {
    info "stopping kubernetes control plane ..."
    for comp in kube-apiserver kube-scheduler kube-controller-manager; do
        nomad::stop_job $comp
    done
    info "kubernetes control plane stopped"
}