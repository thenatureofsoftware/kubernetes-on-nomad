#!/bin/sh

consul::install () {
    wget --quiet https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
    unzip consul_${CONSUL_VERSION}_linux_amd64.zip
    mv consul ${BINDIR}
    rm -f consul_${CONSUL_VERSION}_linux_amd64.zip*
}

consul::enable_service () {
    log "Adding consul service"
    systemctl stop consul.service > /dev/null 2>&1
    systemctl disable consul.service > /dev/null 2>&1

    cp $BASEDIR/consul/consul.service /lib/systemd/system
    mkdir -p /etc/consul
    cp $BASEDIR/consul/consul.json /etc/consul
    
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable consul.service > /dev/null 2>&1
    systemctl start consul.service > /dev/null 2>&1
}

consul::enable_dns () {
    log "Switching to consul as only nameserver..."
    source $BASEDIR/script/iptables.rules
    iptables -t nat -A PREROUTING -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A PREROUTING -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A OUTPUT -d localhost -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A OUTPUT -d localhost -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
    
    USING_CONSUL=$(cat /etc/resolvconf/resolv.conf.d/head | grep "#Using consul")
    if [ "${USING_CONSUL}" == "" ]; then
        info "Adding 127.0.0.1 as nameserver"
        printf "\n#Using consul and consul recursors\nnameserver 127.0.0.1\n" >> /etc/resolvconf/resolv.conf.d/head
        resolvconf -u
        systemctl stop systemd-resolved
    fi

    info "Consul DNS recursors:\n$(cat $BASEDIR/consul/consul.json | jq '.recursors')"
    info "Now using consul as nameserver"
}

consul::put () {
    info "$(consul kv put $1 $2) value: $2"
}

consul::put_file () {
    info "$(consul kv put $1 @$2) value: $2"
}
