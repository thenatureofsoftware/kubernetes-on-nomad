#!/bin/bash

kubelet::install () {
    log "Installing kubelet, kubectl and kubeadm ..."
    
    case "$(common::os)" in
        "Container Linux by CoreOS")
            kubelet::install_by_download
            ;;
        "Ubuntu")
            kubelet::install_by_apt
            ;;
        *)
    esac

    kubelet::download_and_install "kubectl" "$K8S_VERSION"
    kubelet::download_and_install "kubeadm" "$KUBEADM_VERSION"

    info "Done installing Kubernetes components"
}

kubelet::install_by_download () {
    kubelet::download_and_install "kubelet" "$K8S_VERSION"
}

kubelet::install_by_apt () {
    apt-get update > /dev/null 2>&1
    apt-get install -y apt-transport-https > /dev/null 2>&1
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - > /dev/null 2>&1
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    apt-get update > /dev/null 2>&1
    apt-get install -y kubelet=$(echo $K8S_VERSION | sed 's/v//g')-00 > /dev/null 2>&1
    kubelet::reset
}

kubelet::download_and_install() {
    if [ "$1" == "" ] || [ "$2" == "" ]; then
        fail "Both component and version is required, got component:$2 and version:$1"
    fi
    
    info "Downloading and installing: $1 version: $2"
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$2/bin/linux/amd64/$1
    chmod a+x $1
    mv $1 $BINDIR
    info "Done installing $1"
}

kubelet::reset () {
    info "Calling kubeadm reset" "\n$(kubeadm reset)"
    log "Stopping kubelet.service"
    systemctl stop kubelet > /dev/null 2>&1
    log "Disable kubelet.service"
    systemctl disable kubelet > /dev/null 2>&1
    common::rm_all_running_containers
    rm -rf /var/lib/kubelet/* > /dev/null 2>&1
}