#!/bin/bash

###############################################################################
# Installs Consul
###############################################################################
consul::install () {

    if [ $(common::which consul) ]; then
        info "Consul already installed $(consul version)"
        return 0
    fi

    tmpdir=$(mktemp -d kon.XXXXXX)
    download_file=$tmpdir/consul.zip
    curl -o $download_file -sS $(consul::download_url)
    if [ $? -gt 0 ]; then fail "failed to download consul ${CONSUL_VERSION}"; fi
    unzip -qq -o -d ${BINDIR} $download_file
    rm -rf $tmpdir
    ${BINDIR}/consul version > "$(common::dev_null)" 2>&1

    if [ $? -gt 0 ]; then fail "Consul install failed!"; fi
}

consul::download_url () {
    sys_info=$(common::system_info)
    os=$(echo $sys_info|jq -r  .os)
    arch=$(echo $sys_info|jq -r  .arch)
    echo "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_${os}_${arch}.zip"
}

consul::bind_interface () {
    if [ ! "$_arg_interface" == "" ]; then
        CONSUL_BIND_INTERFACE=$_arg_interface
    elif [ ! "$KON_BIND_INTERFACE" == "" ]; then
        CONSUL_BIND_INTERFACE=$KON_BIND_INTERFACE
    else
        error "no network interface for bind address. Set KON_BIND_INTERFACE in config or us --interface <value> argument"
        exit 1
    fi
    info "using bind interface $CONSUL_BIND_INTERFACE"
}

###############################################################################
# Creates a resolv.conf that points to Consul and enables it.
###############################################################################
consul::enable-consul-dns () {
    info "switching nameserver to consul"
    if [ -L /etc/resolv.conf ]; then
        consul::enable-consul-dns-symbolic-link
    else
        consul::enable-consul-dns-file
    fi
}

consul::enable-consul-dns-symbolic-link () {
    if [ ! "$(readlink /etc/resolv.conf)" == "/etc/kon/resolv.conf" ]; then
        info "creating symlink /etc/resolv.conf -> /etc/kon/resolv.conf"
        cat <<EOF > /etc/kon/resolv.conf
#Using Consul as ns
nameserver $(common::ip_addr)    
EOF
        # Used to restore DNS config
        printf "%s" "$(readlink /etc/resolv.conf)" > $KON_CONFIG_DIR/resolv_conf_org
        
        rm /etc/resolv.conf
        ln -s /etc/kon/resolv.conf /etc/resolv.conf
    fi
}

consul::enable-consul-dns-file () {
    if [ ! -f /etc/resolv.conf.org ]; then
        mv /etc/resolv.conf /etc/resolv.conf.org
    fi
    cat <<EOF > /etc/resolv.conf
#Using Consul as ns
nameserver $(common::ip_addr)
EOF
}

###############################################################################
# Restores the /etc/resolv.conf symbolic link.
###############################################################################
consul::disable-consul-dns () {
    if [ -L /etc/resolv.conf ]; then
        consul::disable-consul-dns-symbolic-link
    else
        consul::disable-consul-dns-file
    fi
}

consul::disable-consul-dns-symbolic-link () {
    if [ ! -f "$KON_CONFIG_DIR/resolv_conf_org" ]; then
        fail "no resolv.conf target found, can't restore."
    fi
    org_link_target=$(cat $KON_CONFIG_DIR/resolv_conf_org)

    if [ ! -L /etc/resolv.conf ]; then
        fail "/etc/resolv.conf is'nt a symbolik link, can't restore"
    fi
    
    rm /etc/resolv.conf
    ln -s $org_link_target /etc/resolv.conf
    if [ $? -gt 0 ]; then fail "failed to restore DNS config!"; fi
}

consul::disable-consul-dns-file () {
    if [ -f /etc/resolv.conf.org ]; then
        rm -f /etc/resolv.conf
        mv /etc/resolv.conf.org /etc/resolv.conf
    fi
}

consul::start-bootstrap () {

    if [ -n "$KON_DEV" ]; then fail "Can't start bootstrap in development mode, use nomad start instead."; fi

    # Save the current nameserver
    kon_nameserver=$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')
    if [ "$kon_nameserver" == "" ] || [ "$kon_nameserver" == "127.0.0.1" ]; then
        fail "Invalid nameserver for consul recursors: $kon_nameserver"
    fi

    consul::bind_interface
    consul::check_start_params
    info "starting Consul ..."

    docker run -d --name kon-consul \
    --restart=always \
    --network=host \
    -v /var/lib/consul:/consul/data \
    -v /etc/consul:/consul/config \
    -v /etc/kon/pki:/etc/kon/pki \
    -e 'CONSUL_ALLOW_PRIVILEGED_PORTS=true' \
    -e 'CONSUL_CLIENT_INTERFACE=lo' \
    -e "CONSUL_BIND_INTERFACE=$CONSUL_BIND_INTERFACE" \
    consul:$CONSUL_VERSION agent -server \
    -dns-port=53 \
    -recursor=$kon_nameserver \
    -datacenter="$(config::get_dc)" \
    -encrypt=$KON_CONSUL_ENCRYPTION_KEY \
    -bootstrap-expect=1 > $(common::dev_null) 2>&1

    consul::enable-consul-dns
}

consul::start () {

    if [ -z "$KON_SEVERS"]; then
        info "is server: $(config::is_server), server list: $KON_SERVERS, ip address: $(common::ip_addr)"
    fi

    if [ "$(config::is_server)" == "true" ]; then
        agent_type="agent -server"
    else
        agent_type="agent"
    fi

    if [ "$kon_nameserver" == "" ]; then
        kon_nameserver=$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')
        if [ "$kon_nameserver" == "" ] || [ "$kon_nameserver" == "127.0.0.1" ]; then
            fail "invalid nameserver for consul recursors: $kon_nameserver"
        fi
    fi

    if [ -n "$KON_DEV" ]; then
        consul::start_dev
        common::fail_on_error "failed to start consul in development mode."
        return 0;
    fi

    consul::bind_interface
    consul::check_start_params
    info "starting Consul $agent_type in datacenter:$(config::get_dc) ..."

    docker run -d --name kon-consul \
    --restart=always \
    --network=host \
    -v /var/lib/consul:/consul/data \
    -v /etc/consul:/consul/config \
    -v /etc/kon/pki:/etc/kon/pki \
    -e 'CONSUL_ALLOW_PRIVILEGED_PORTS=true' \
    -e 'CONSUL_CLIENT_INTERFACE=lo' \
    -e "CONSUL_BIND_INTERFACE=$CONSUL_BIND_INTERFACE" \
    consul:$CONSUL_VERSION $agent_type \
    -dns-port=53 \
    -recursor=$kon_nameserver \
    -retry-join=$KON_BOOTSTRAP_SERVER \
    -datacenter="$(config::get_dc)" \
    -encrypt=$KON_CONSUL_ENCRYPTION_KEY > $(common::dev_null) 2>&1

    consul::enable-consul-dns
}

consul::start_dev () {
    consul::bind_interface
    consul::check_start_params
    info "starting Consul in development mode and in datacenter:$(config::get_dc) ..."

    docker run -d --name kon-consul \
    --restart=always \
    --network=host \
    -v /var/lib/consul:/consul/data \
    -v /etc/consul:/consul/config \
    -v /etc/kon/pki:/etc/kon/pki \
    -e 'CONSUL_ALLOW_PRIVILEGED_PORTS=true' \
    -e 'CONSUL_CLIENT_INTERFACE=lo' \
    -e "CONSUL_BIND_INTERFACE=$CONSUL_BIND_INTERFACE" \
    consul:$CONSUL_VERSION agent -dev \
    -recursor=$kon_nameserver \
    -datacenter=$(config::get_dc) \
    -encrypt=$KON_CONSUL_ENCRYPTION_KEY > $(common::dev_null) 2>&1

    consul::enable-consul-dns   
}

consul::check_start_params () {
    if [ ! $kon_nameserver ]; then fail "no recursor"; fi
    if [ ! $CONSUL_BIND_INTERFACE ]; then fail "no network interface"; fi
    if [ ! $CONSUL_VERSION ]; then fail "no Consul version"; fi
    if [ ! $KON_CONSUL_ENCRYPTION_KEY ]; then fail "no encryption key"; fi
    if [ ! -f "$KON_CONSUL_CONFIG_TLS" ]; then fail "no Consul TLS config"; fi
    pki::check_ca_cert
    pki::check_consul
}

###############################################################################
# Restores the DNS config and stopps the Consul docker container.
###############################################################################
consul::stop () {
    consul::disable-consul-dns
    docker stop kon-consul > $(common::dev_null) 2>&1
    docker rm -f kon-consul > $(common::dev_null) 2>&1
}

consul::wait_for_started () {
    for (( ;; )); do
        sleep 10
        info "waiting for consul to start..."
        if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
            info "bootstrap Consul started!"
            consul members $(common::dev_null) 2>&1
            if [ $? -eq 0 ]; then break; fi
        fi 
    done
}

consul::put () {
    if [ "$1" == "" ] || [ "$2" == "" ]; then fail "invalid argument, key or value can't be empty"; fi
    
    local key=$1
    local value=""
    
    if [ "$2" == "-" ]; then
        value=""
    else
        value=$2
    fi
    
    info "$(consul kv put "$key" "$value") value: $value"
}

###############################################################################
# Checks if Consul has key.
# Param #1 key
# echo "true" if key exists and return 0 else return 1
###############################################################################
consul::has_key () {
    if [ "$1" == "" ]; then return 0; fi
    
    consul kv get $1 > $(common::dev_null) 2>&1
    if [ $? -eq 0 ]; then
        echo "true"
        return 0
    fi
}
consul::get () {
    if [ "$(consul::has_key $1)" ]; then echo "$(consul kv get $1)"; fi
}

consul::delete_all () {
    if [ "$1" == "" ]; then fail "invalid first argument, can't be empty"; fi
    consul kv delete -recurse $1 > $(common::dev_null) 2>&1
    common::fail_on_error "delete of key:$1 failed"
}

consul::delete () {
    if [ "$1" == "" ]; then fail "invalid first argument, can't be empty"; fi
    consul kv delete $1 > $(common::dev_null) 2>&1
    common::fail_on_error "delete of key:$1 failed"
}

consul::fail_if_missing_key () {
    if [ "$(consul::has_key $1)" ]; then
        echo "$(consul kv get $1)";
    else
        fail "$2"
    fi
}

consul::put_file () {
    info "$(consul kv put $1 @$2) value: $2"
}

consul::generate_encryption_key () {
    if [ ! "$(common::which consul)" == "" ]; then
        consul_encryption_key=$(consul keygen)
        if [ $? -gt 0 ]; then fail "consul failed to generate encryption key"; fi
    else
        consul_encryption_key=$(docker run --rm -it consul keygen)
        if [ $? -gt 0 ]; then fail "failed to generate encryption key using consul Docker image"; fi
    fi
    echo "$(echo -e "${consul_encryption_key}" | tr -d '[:space:]')"
}

consul::is_running () {
    if [ $(docker ps -q -f "name=kon-consul") ]; then
        echo "true"
    fi
}

consul::write_tls_config () {
    ip_addr=$(common::ip_addr)
    cert_bundle=$(pki::generate_name "consul" "$ip_addr")
    mkdir -p $KON_CONSUL_CONFIG_DIR
    cat << EOF > $KON_CONSUL_CONFIG_TLS
{
  "verify_server_hostname": true,
  "verify_incoming": true,
  "verify_outgoing": true,
  "key_file": "/etc/kon/pki/${cert_bundle}.key",
  "cert_file": "/etc/kon/pki/${cert_bundle}.crt",
  "ca_file": "/etc/kon/pki/ca.crt",
  "addresses": {
    "dns": "${ip_addr} 127.0.0.1"
  },
  "ports": {
    "dns": 53
  }
}
EOF
}

