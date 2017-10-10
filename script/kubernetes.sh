#!/bin/bash

kubernetes::install () {
    log "Installing kubelet, kubectl and kubeadm ..."
    
    case "$(common::os)" in
        "Container Linux by CoreOS")
            kubernetes::install_by_download
            ;;
        "Ubuntu")
            kubernetes::install_by_apt
            ;;
        *)
    esac
    common::fail_on_error "Failed to install kubelet"

    kubernetes::download_and_install "kubectl" "$K8S_VERSION"
    common::fail_on_error "Failed to install kubectl"
    
    kubernetes::download_and_install "kubeadm" "$KUBEADM_VERSION"
    common::fail_on_error "Failed to install kubeadm"

    info "Done installing Kubernetes components"
}

kubernetes::install_by_download () {
    kubernetes::download_and_install "kubelet" "$K8S_VERSION"
    common::fail_on_error "Failed to install kubelet"
    mkdir -p /etc/kubernetes/manifests

    kubernetes::download_and_install "kube-apiserver" "$K8S_VERSION"
    common::fail_on_error "Failed to install kube-apiserver"
    
    kubernetes::download_and_install "kube-scheduler" "$K8S_VERSION"
    common::fail_on_error "Failed to install kube-scheduler"

    kubernetes::download_and_install "kube-controller-manager" "$K8S_VERSION"
    common::fail_on_error "Failed to install kube-controller-manager"

    info "Installing cni plugins..."
    if [ "$CNI_VERSION" == "" ]; then fail "CNI_VERSION is not set, is KON_CONFIG loaded?"; fi

    info "$CNI_VERSION"
    mkdir -p /opt/cni/bin
    curl -sL https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-amd64-$CNI_VERSION.tgz | tar zxv -C /opt/cni/bin > "$(common::dev_null)" 2>&1
    common::fail_on_error "Failed to download cni plugins"
}

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

kubernetes::download_and_install() {
    if [ "$1" == "" ] || [ "$2" == "" ]; then
        fail "Both component and version is required, got component:$2 and version:$1"
    fi

    info "Downloading and installing: $1 version: $2"
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$2/bin/linux/amd64/$1
    chmod a+x $1
    mv $1 $BINDIR
    info "Done installing $1"
}

###############################################################################
# Stopps and removes kubernetes.
###############################################################################
kubernetes::reset () {
    nomad stop kube-control-plane
    common::error_on_error "Failed to stop kubernetes control-plane in Nomad."

    nomad stop kubelet
    common::error_on_error "Failed to stop kubelet in Nomad."

    consul kv delete -recurse kubernetes
    common::error_on_error "Failed to delete kubernetes key in Consul."
}