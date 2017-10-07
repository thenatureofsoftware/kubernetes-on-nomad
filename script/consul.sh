#!/bin/sh

###############################################################################
# Installs Consul
###############################################################################
consul::install () {
    # Download Consul
    wget --quiet https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
    if [ $? -gt 0 ]; then fail "Failed to download Consul ${CONSUL_VERSION}"; fi

    common::mk_bindir
    
    tmpdir=$(mktemp -d kon.XXXXXX)
    unzip -d $tmpdir consul_${CONSUL_VERSION}_linux_amd64.zip
    mv $tmpdir/consul ${BINDIR}/
    rm -f consul_${CONSUL_VERSION}_linux_amd64.zip*
    
    # Check consul is working
    consul version > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        info "$(consul version|grep Consul) installed"
    else
        fail "Consull install failed!"
    fi
}

consul::bind_interface () {
    if [ ! "$_arg_interface" == "" ]; then
        CONSUL_BIND_INTERFACE=$_arg_interface
    elif [ ! "$KON_BIND_INTERFACE" == "" ]; then
        CONSUL_BIND_INTERFACE=$KON_BIND_INTERFACE
    else
        error "No network interface for bind address. Set KON_BIND_INTERFACE in config or us --interface <value> argument"
        exit 1
    fi
    info "Using bind interface $CONSUL_BIND_INTERFACE"
}

###############################################################################
# Creates a resolv.conf that points to Consul and enables it.
###############################################################################
consul::enable-consul-dns () {
    if [ -L /etc/resolv.conf ] && [ ! "$(readlink /etc/resolv.conf)" == "/etc/kon/resolv.conf" ]; then
        info "Creating symlink /etc/resolv.conf -> /etc/kon/resolv.conf"
        cat <<EOF > /etc/kon/resolv.conf
#Using Consul as ns
nameserver 127.0.0.1    
EOF
        # Used to restore DNS config
        printf "%s" "$(readlink /etc/resolv.conf)" > $KON_INSTALL_DIR/resolv_conf_org
        
        rm /etc/resolv.conf
        ln -s /etc/kon/resolv.conf /etc/resolv.conf
    fi
}

###############################################################################
# Restores the /etc/resolv.conf symbolic link.
###############################################################################
consul::disable-consul-dns () {
    if [ ! -f "$KON_INSTALL_DIR/resolv_conf_org" ]; then
        fail "No resolv.conf target found, can't restore."
    fi
    org_link_target=$(cat $KON_INSTALL_DIR/resolv_conf_org)

    if [ ! -L /etc/resolv.conf ]; then
        fail "/etc/resolv.conf is'nt a symbolik link, can't restore"
    fi
    
    rm /etc/resolv.conf
    ln -s $org_link_target /etc/resolv.conf
    if [ $? -gt 0 ]; then fail "Failed to restore DNS config!"; fi
}

consul::start-bootstrap () {
    # Save the current nameserver
    kon_nameserver=$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')
    if [ "$kon_nameserver" == "" ] || [ "$kon_nameserver" == "127.0.0.1" ]; then
        fail "Invalid nameserver for consul recursors: $kon_nameserver"
    fi

    info "Starting Consul ..."
    consul::bind_interface
    docker run -d --name kon-consul \
    --restart=always \
    --network=host \
    --memory=500m \
    -v /var/lib/consul:/consul/data \
    -e 'CONSUL_ALLOW_PRIVILEGED_PORTS=true' \
    -e 'CONSUL_CLIENT_INTERFACE=lo' \
    -e "CONSUL_BIND_INTERFACE=$CONSUL_BIND_INTERFACE" \
    consul:$CONSUL_VERSION agent -server \
    -dns-port=53 \
    -recursor=$kon_nameserver \
    -bootstrap-expect=1

    info "Switching nameserver to consul"
    consul::enable-consul-dns
}

consul::start () {

    if [ -z "$KON_SEVERS"]; then
        info "Is server: $(common::is_server), server list: $KON_SEVERS, ip address: $(common::ip_addr)"
    fi

    if [ "$(common::is_server)" == "true" ]; then
        agent_type="agent -server"
    else
        agent_type="agent"
    fi

    if [ "$kon_nameserver" == "" ]; then
        kon_nameserver=$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')
        if [ "$kon_nameserver" == "" ] || [ "$kon_nameserver" == "127.0.0.1" ]; then
            fail "Invalid nameserver for consul recursors: $kon_nameserver"
        fi
    fi

    info "Starting Consul $agent_type ..."
    consul::bind_interface

    docker run -d --name kon-consul \
    --restart=always \
    --network=host \
    --memory=500m \
    -v /var/lib/consul:/consul/data \
    -e 'CONSUL_ALLOW_PRIVILEGED_PORTS=true' \
    -e 'CONSUL_CLIENT_INTERFACE=lo' \
    -e "CONSUL_BIND_INTERFACE=$CONSUL_BIND_INTERFACE" \
    consul:$CONSUL_VERSION $agent_type \
    -dns-port=53 \
    -recursor=$kon_nameserver \
    -retry-join=$KON_BOOTSTRAP_SERVER

    info "Switching nameserver to consul"
    consul::enable-consul-dns
}

consul::stop () {
    docker stop kon-consul
    docker rm -f kon-consul
}

consul::wait_for_started () {
    for (( ;; )); do
        sleep 10
        info "Waiting for consul to start..."
        if [ "$(docker ps -f 'name=kon-consul' --format '{{.Names}}')" == "kon-consul" ]; then
            info "Bootstrap Consul started!"
            break;
        fi 
    done
}

consul::put () {
    info "$(consul kv put $1 $2) value: $2"
}

consul::put_file () {
    info "$(consul kv put $1 @$2) value: $2"
}

