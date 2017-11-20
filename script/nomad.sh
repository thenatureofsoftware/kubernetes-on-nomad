#!/bin/sh

nomad::env () {
    local ip_addr="$(common::ip_addr)"
    local region="$(config::get_region "$ip_addr")"
    local hostname="$(config::get_host "$ip_addr")"
    cat <<EOF
export NOMAD_ADDR=https://localhost:4646
export NOMAD_REGION=$region
export NOMAD_CACERT=$KON_PKI_DIR/ca.crt
export NOMAD_CLIENT_CERT=$KON_PKI_DIR/$hostname.crt
export NOMAD_CLIENT_KEY=$KON_PKI_DIR/$hostname.key
EOF
}

nomad::install () {
    if [ $(common::which nomad) ]; then
        info "Nomad already installed $(nomad version)"
        return 0
    fi
    info "downloading nomad version ${NOMAD_VERSION}..."
    tmpdir=$(mktemp -d kon.XXXXXX)
    curl -o $tmpdir/nomad.zip -sS $(nomad::download_url)
    if [ $? -gt 0 ]; then fail "failed to download nomad ${NOMAD_VERSION}"; fi
    unzip -qq -o -d ${BINDIR} $tmpdir/nomad.zip
    rm -rf $tmpdir
    ${BINDIR}/nomad version > "$(common::dev_null)" 2>&1

    if [ $? -gt 0 ]; then fail "Nomad install failed!"; fi
    info "nomad version ${NOMAD_VERSION} installed in ${BINDIR}"
}

nomad::download_url () {
    sys_info=$(common::system_info)
    os=$(echo $sys_info|jq -r  .os)
    arch=$(echo $sys_info|jq -r  .arch)
    echo "https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_${os}_${arch}.zip"
}

nomad::start () {
    if [ ! "$(common::which nomad)" ]; then fail "Nomad not installed, please install nomad first."; fi
    if [ ! -f "$(nomad::resolve_nomad_service_unit_file)" ]; then
        nomad::deploy_service_unit
    else
        info "restarting nomad service..."
        systemctl restart nomad > "$(common::dev_null)" 2>&1
        info "nomad service restarted"
    fi
}

nomad::stop () {
    if [ -f "$(nomad::resolve_nomad_service_unit_file)" ]; then
        systemctl stop nomad > "$(common::dev_null)" 2>&1
    fi
}

nomad::deploy_service_unit () {
    mkdir -p /etc/nomad
    info "installing nomad service for os $(common::os) ..."

    nomad_service_unit_file=$(nomad::resolve_nomad_service_unit_file)
    nomad_advertise_ip=$(common::ip_addr)

    if [ "$KON_DEV" == "true" ]; then
        info "generating Nomad dev config"
        nomad::service_template $nomad_service_unit_file "-dev"
        nomad::dev_template "/etc/nomad/dev.hcl" "$nomad_advertise_ip"
    elif [ "$(config::is_server)" == "true" ]; then
        info "generating Nomad server config"
        nomad::service_template $nomad_service_unit_file
        nomad::server_template "/etc/nomad/server.hcl" "$nomad_advertise_ip"
    else
        info "generating Nomad client config"
        nomad::service_template $nomad_service_unit_file
        nomad::client_config "/etc/nomad/client.hcl" "$nomad_advertise_ip"
    fi

    systemctl daemon-reload > "$(common::dev_null)" 2>&1
    systemctl disable nomad.service > "$(common::dev_null)" 2>&1
    systemctl enable nomad.service > "$(common::dev_null)" 2>&1
    systemctl restart nomad.service > "$(common::dev_null)" 2>&1
    info "nomad service installed and started"
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

nomad::bootstrap_expected () {
    echo ${#config_servers[@]}
}

###############################################################################
# Generates the nomad client servers config.
###############################################################################
nomad::servers_config () {
    arg_servers="$1"
    if [ "$arg_servers" == "" ]; then
        arg_servers="$KON_SERVERS"
        if [ "$arg_servers" == "" ]; then
            fail "KON_SERVERS is not set, is KON_CONFIG loaded?"; return 1
        fi
    fi

    strings=()
    nomad_servers=()
    IFS=', ' read -r -a strings <<< $arg_servers
    for elem in "${strings[@]}"; do
        ip_addr=$(config::node_ip $elem)
        nomad_servers+=("\"$ip_addr\"")
    done
    _test_="[$(common::join_by , "${nomad_servers[@]}")]"
    echo $_test_
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
    if [ ! -n "$ETCD_INITIAL_CLUSTER" ]; then fail "ETCD_INITIAL_CLUSTER is not set, is KON_CONFIG loaded?"; fi
    if [ ! -n "$KON_MINIONS" ]; then fail "KON_MINIONS is not set, is KON_CONFIG loaded?"; fi

    # Resolve ip-address
    if [ ! -n "$nomad_advertise_ip" ]; then
        if [ ! -n "$2" ]; then fail "nomad_advertise_ip is not set"; else
            nomad_advertise_ip=$1
        fi
    fi
    info "configuring Nomad client for IP $nomad_advertise_ip"

    # Check if this is an etcd node
    if [ -n "$(echo $ETCD_INITIAL_CLUSTER | grep $nomad_advertise_ip)" ]; then
        node_class+=('etcd')
    fi

    if [ -n "$(echo $KON_MINIONS | grep $nomad_advertise_ip)" ]; then
        node_class+=('kubelet')
    fi

    node_class=$(common::join_by , "${node_class[@]}")
    nomad::client_template $1 "$nomad_advertise_ip" "$node_class" "$(nomad::servers_config)"

    _test_=$node_class
}

###############################################################################
# Runs a Nomad job
# Param $1 - job name ( ${JOBDIR}/$1.nomad )
###############################################################################
nomad::run_job () {
    if [ "$1" == "" ]; then fail "job name can't be empty, did you forgett the argument?"; fi
    local job_name="$1"

    eval $(nomad::env)
    for region in ${!config_regions[@]}; do
        info "running nomad job $job_name in region $region"
        cat $JOBDIR/${job_name}.nomad | config::configure_job $region | nomad run -detach -region=$region -
        common::fail_on_error "failed to run $job_name."
    done 

    sleep 3
    info "$job_name job $(nomad job status $job_name | grep "^Status")"
    consul::put "$stateKey/$job_name" $STARTED
}

###############################################################################
# Stopps a Nomad job
# Param $1 - job name
###############################################################################
nomad::stop_job () {
    if [ "$1" == "" ]; then fail "job name can't be empty, did you forgett the argument?"; fi
    local job_name="$1"

    if [ ! "$(consul::get $stateKey/$job_name)" == $STARTED ]; then warn "$job_name not started"; fi

    eval $(nomad::env)
    nomad stop -purge $job_name > $(common::dev_null) 2>&1
    common::error_on_error "failed to stop $job_name."
    consul::put "$stateKey/$job_name" $STOPPED
}

nomad::service_template () {
  cat <<EOF > $1
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/

[Service]
EnvironmentFile=-/etc/nomad/nomad.env
ExecStart=$BINDIR/nomad agent -encrypt $KON_NOMAD_ENCRYPTION_KEY -region $(config::get_region) -dc $(config::get_dc) -config /etc/nomad $2
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target  
EOF
}

nomad::client_template () {
    cert_bundle=$(pki::generate_name "nomad" "$(common::ip_addr)")
    KON_NOMAD_VERIFY_SERVER_HOSTNAME="true"
    KON_NOMAD_VERIFY_HTTPS_CLIENT="true"
    if [ "$KON_DEV" == "true" ]; then
        KON_NOMAD_VERIFY_SERVER_HOSTNAME="false"
        KON_NOMAD_VERIFY_HTTPS_CLIENT="false"
    fi

    cat <<EOF > "$1"

data_dir = "/var/lib/nomad"

bind_addr = "0.0.0.0"

advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}

client {
  enabled = true
  network_interface = "$KON_BIND_INTERFACE"
  servers = ${4}
  node_class = "${3}"
  no_host_uuid = false
  $KON_NETWORK_SPEED

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

tls {
  http = true
  rpc  = true
  ca_file = "${KON_PKI_DIR}/ca.crt"
  cert_file = "${KON_PKI_DIR}/${cert_bundle}.crt"
  key_file = "${KON_PKI_DIR}/${cert_bundle}.key"
  verify_server_hostname = ${KON_NOMAD_VERIFY_SERVER_HOSTNAME}
  verify_https_client    = ${KON_NOMAD_VERIFY_HTTPS_CLIENT}
}
EOF
}

nomad::server_template() {
    cert_bundle=$(pki::generate_name "nomad" "$(common::ip_addr)")
    cat <<EOF > $1

data_dir = "/var/lib/nomad"

bind_addr = "0.0.0.0"

advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}

server { 
 enabled = true 
 bootstrap_expect = $(nomad::bootstrap_expected) 
}

consul {
  address = "127.0.0.1:8500"
}

tls {
  http = true
  rpc  = true
  ca_file = "${KON_PKI_DIR}/ca.crt"
  cert_file = "${KON_PKI_DIR}/${cert_bundle}.crt"
  key_file = "${KON_PKI_DIR}/${cert_bundle}.key"
  verify_server_hostname = true
  verify_https_client    = true
} 
EOF
}

nomad::dev_template() {
    cert_bundle=$(pki::generate_name "nomad" "$(common::ip_addr)")
    cat <<EOF > "$1"

data_dir = "/var/lib/nomad"

bind_addr = "0.0.0.0"

advertise {
 http = "${2}"
 rpc  = "${2}"
 serf = "${2}"
}

client {
  node_class = "etcd,kubelet"
  no_host_uuid = false
  network_interface = "$KON_BIND_INTERFACE"
  enabled = true
  options = {
    "driver.raw_exec.enable" = "1"
    "driver.whitelist" = "docker,raw_exec,exec,java"
    "user.checked_drivers" = "exec"
    "docker.privileged.enabled" = "true"
  }
}

server { 
 enabled = true  
}

tls {
  http = true
  rpc  = true
  ca_file = "${KON_PKI_DIR}/ca.crt"
  cert_file = "${KON_PKI_DIR}/${cert_bundle}.crt"
  key_file = "${KON_PKI_DIR}/${cert_bundle}.key"
  verify_server_hostname = true
  verify_https_client    = true
}
EOF
}