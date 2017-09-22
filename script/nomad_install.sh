#!/bin/sh

nomad::install () {
    wget --quiet https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip
    unzip nomad_${NOMAD_VERSION}_linux_amd64.zip
    mv nomad ${BINDIR}
    rm -f nomad_${NOMAD_VERSION}_linux_amd64.zip*
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

