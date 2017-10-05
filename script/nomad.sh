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
    log "OS: $(common::os)"
    nomad_service_unit_file=$(nomad::resolve_nomad_service_unit_file)
    nomad::service_template $nomad_service_unit_file
    nomad_advertise_ip=$(common::ip_addr)
    if [ "$(common::is_server)" == "true" ]; then
        info "Generating Nomad server config"
        nomad::server_template "/etc/nomad/server.hcl" "$nomad_advertise_ip"
    else
        info "Generating Nomad client config"
        nomad::client_template "/etc/nomad/client.hcl" "$nomad_advertise_ip"
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

nomad::service_template() {
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
  cat <<EOF > $1
bind_addr = "0.0.0.0"
data_dir = "/var/lib/nomad/"
advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}
client {
  enabled = true
  servers = ["${KON_BOOTSTRAP_SERVER}"]
  node_class = "etcd"

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