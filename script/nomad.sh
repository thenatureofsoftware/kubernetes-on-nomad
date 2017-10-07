#!/bin/sh

nomad::install () {
    wget --quiet https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip
    
    if [ $? -gt 0 ]; then fail "Failed to download nomad ${NOMAD_VERSION}"; fi
    
    tmpdir=$(mktemp -d kon.XXXXXX)
    unzip -d $tmpdir nomad_${NOMAD_VERSION}_linux_amd64.zip
    mv $tmpdir/nomad ${BINDIR}/
    rm -f nomad_${NOMAD_VERSION}_linux_amd64.zip*
    nomad version > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        info "$(nomad version) installed"
        nomad::deploy_service_unit
    else
        error "Nomad install failed!"
    fi
}

nomad::deploy_service_unit () {
    mkdir -p /etc/nomad
    log "OS: $(common::os)"
    nomad_service_unit_file=$(nomad::resolve_nomad_service_unit_file)
    nomad::service_template $nomad_service_unit_file
    nomad_advertise_ip=$(common::ip_addr)
    if [ "$(common::is_server)" == "true" ]; then
        info "Generating Nomad server config"
        nomad::server_template "/etc/nomad/server.hcl" "$nomad_advertise_ip"
    else
        info "Generating Nomad client config"
        nomad::client_config "/etc/nomad/client.hcl" "$nomad_advertise_ip"
    fi
    systemctl daemon-reload > /dev/null 2>&1
    systemctl disable nomad.service > /dev/null 2>&1
    systemctl enable nomad.service > /dev/null 2>&1
    systemctl restart nomad.service > /dev/null 2>&1
}

nomad::resolve_nomad_service_unit_file () {
    case "$(common::os)" in
        "Container Linux by CoreOS")
            echo "/etc/systemd/system/nomad.service"
            ;;
        "Ubuntu")
            echo "/lib/systemd/system/nomad.service"
            ;;
        *)
    esac
}

nomad::enable_service () {
    sudo mkdir -p /etc/nomad

    if [ "$SERVER" = "true" ]; then
        sed -e "s/\${ADVERTISE_IP}/${ADVERTISE_IP}/g" "$BASEDIR/nomad/server.hcl.tmpl" > /etc/nomad/server.hcl
    else
        sed -e "s/\${ADVERTISE_IP}/${ADVERTISE_IP}/g" -e "s/\${SERVER_IP}/${SERVER_IP}/g" "$BASEDIR/nomad/client.hcl.tmpl" > /etc/nomad/client.hcl
    fi

    cp $BASEDIR/nomad/nomad.service /lib/systemd/system
    systemctl daemon-reload > /dev/null 2>&1
    systemctl disable nomad.service > /dev/null 2>&1
    systemctl enable nomad.service > /dev/null 2>&1
    systemctl restart nomad.service > /dev/null 2>&1
}

###############################################################################
# Creates a Nomad client config (client.hcl)
# Param $1 - filename where to write the config
# Param $2 - Nomad adverties IP-address (only used if) $nomad_advertise_ip
#            is not set.
###############################################################################
nomad::client_config () {
    # node_class variable
    node_class=()
    if [ ! -n "$ETCD_INITIAL_CLUSTER" ]; then fail "ETCD_INITIAL_CLUSTER is not set is KON_CONFIG loaded?"; fi
    if [ ! -n "$KUBE_MINIONS" ]; then fail "KUBE_MINIONS is not set is KON_CONFIG loaded?"; fi

    # Resolve ip-address
    if [ ! -n "$nomad_advertise_ip" ]; then
        if [ ! -n "$2" ]; then fail "nomad_advertise_ip is not set"; else
            nomad_advertise_ip=$1
        fi
    fi
    info "Configuring Nomad client for IP $nomad_advertise_ip"

    # Check if this is an etcd node
    if [ -n "$(echo $ETCD_INITIAL_CLUSTER | grep $nomad_advertise_ip)" ]; then
        node_class+=('etcd')
    fi

    if [ -n "$(echo $KUBE_MINIONS | grep $nomad_advertise_ip)" ]; then
        node_class+=('kubelet')
    fi

    node_class=$(common::join_by , "${node_class[@]}")
    nomad::client_template $1 "$nomad_advertise_ip" "$node_class"

    _test_=$node_class
}

nomad::service_template () {
  cat <<EOF > $1
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/

[Service]
EnvironmentFile=-/etc/nomad/nomad.env
ExecStart=$BINDIR/nomad agent -config /etc/nomad
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target  
EOF
}

nomad::client_template() {
  cat <<EOF > "$1"
bind_addr = "0.0.0.0"
data_dir = "/var/lib/nomad/"
advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}
client {
  enabled = true
  network_interface = "$KON_BIND_INTERFACE"
  servers = ["${KON_BOOTSTRAP_SERVER}"]
  node_class = "${3}"

  options = {
    "driver.raw_exec.enable" = "1"
    "driver.whitelist" = "docker,raw_exec,exec,java"
    "user.checked_drivers" = "exec"
    "docker.privileged.enabled" = "true"
  }
}
consul {
  address = "127.0.0.1:8500"
}
EOF
}

nomad::server_template() {
  cat <<EOF > $1
bind_addr = "0.0.0.0"
data_dir = "/var/lib/nomad"
advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}
server { 
 enabled = true 
 bootstrap_expect = 1 
}
consul {
  address = "127.0.0.1:8500"
} 
EOF
}