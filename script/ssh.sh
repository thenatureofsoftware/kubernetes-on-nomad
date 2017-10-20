#!/bin/bash

ssh::cmd () {
    if [ "$_test_" == "true" ]; then
        echo "cat"
    elif [ "$KON_VAGRANT_SSH" == "true" ]; then
        echo "vagrant ssh $(ssh::host)"
    else
        echo "ssh $(ssh::user)$(ssh::host)"
    fi
}

ssh::user () {
    if [ ! "$KON_SSH_USER" == "" ]; then echo "$KON_SSH_USER@"; fi
}

ssh::host () {
    echo "$KON_SSH_HOST"
}

ssh::ping () {
    $(ssh::cmd) << EOF
sudo echo ping
EOF
}

ssh::copy () {
    ip_addr=$1
    if [ ! "$ip_addr" ]; then fail "ip_addr is missing"; fi
    consul_cert_bundle_name="$(pki::generate_name "consul" "$ip_addr")"
    nomad_cert_bundle_name="$(pki::generate_name "nomad" "$ip_addr")"

    (
    cd $KON_PKI_DIR
    rm -f pki.tgz
    tar zcvf pki.tgz $consul_cert_bundle_name.* $nomad_cert_bundle_name.* ca.crt
    cd -
    )

    if [ "$_test_" == "true" ]; then
        echo "copy active_config=$active_config"
    elif [ "$KON_VAGRANT_SSH" == "true" ]; then
        vagrant scp $active_config $(ssh::host):~/
        vagrant scp $BASEDIR/kon $(ssh::host):~/
        vagrant scp $KON_PKI_DIR/pki.tgz $(ssh::host):~/
    else
        scp $active_config $(ssh::user)$(ssh::host):~/
        scp $BASEDIR/kon $(ssh::user)$(ssh::host):~/
        scp $KON_PKI_DIR/pki.tgz $(ssh::user)$(ssh::host):~/
    fi
}

ssh::install_kon () {
    if [ "$KON_DEV" == "true" ]; then
        $(ssh::cmd) << EOF
sudo /kon-dev/update-all.sh \
&& sudo mkdir -p /etc/kon/pki \
&& sudo tar zxvf ~/pki.tgz -C /etc/kon/pki/
EOF
    else
        $(ssh::cmd) << EOF
sudo mkdir -p /opt/bin \
&& sudo mkdir -p /etc/kon/pki \
&& sudo mv ~/kon /opt/bin \
&& sudo chmod a+x /opt/bin/kon \
&& sudo mkdir -p /etc/kon \
&& sudo mv ~/kon.conf /etc/kon/ \
&& sudo tar zxvf ~/pki.tgz -C /etc/kon/pki/
EOF
    fi
}

ssh::setup_node () {
    $(ssh::cmd) << EOF
sudo /opt/bin/kon setup node
EOF
}
