#!/bin/bash

vault::install () {
    wget --quiet https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
    unzip vault_${VAULT_VERSION}_linux_amd64.zip
    mv vault ${BINDIR}
    rm -f vautl_${VAULT_VERSION}_linux_amd64.zip*
}

vault::enable_service () {
    log "Adding vault service"
    systemctl stop vault.service > /dev/null 2>&1
    systemctl disable vault.service > /dev/null 2>&1

    cp $BASEDIR/vault/vault.service /lib/systemd/system
    mkdir -p /etc/vault
    cp $BASEDIR/vault/server.hcl /etc/vault

    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable vault.service > /dev/null 2>&1
    systemctl start vault.service > /dev/null 2>&1
}