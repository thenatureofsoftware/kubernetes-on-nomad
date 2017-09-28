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
    systemctl stop systemd-resolved
    if [ -f /etc/resolv.conf.org ]; then
      log "Restoring /etc/resolv.conf"
      cp /etc/resolv.conf.org /etc/resolv.conf 
    else
      log "Saving original /etc/resolv.conf"
      mv /etc/resolv.conf /etc/resolv.conf.org
      cp /etc/resolv.conf.org /etc/resolv.conf
    fi
    source $BASEDIR/script/iptables.rules
    iptables -t nat -A PREROUTING -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A PREROUTING -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A OUTPUT -d localhost -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
    iptables -t nat -A OUTPUT -d localhost -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
    log "Consul DNS recursors:\n$(cat $BASEDIR/consul/consul.json | jq '.recursors')"
    log "Now using consul as nameserver"
}

consul::put () {
    log "$(consul kv put $1 $2) value: $2"
}

consul::put_file () {
    log "$(consul kv put $1 @$2) value: $2"
}
