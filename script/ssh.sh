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
    if [ "$_test_" == "true" ]; then
        echo "copy active_config=$active_config"
    elif [ "$KON_VAGRANT_SSH" == "true" ]; then
        vagrant scp $active_config $(ssh::host):~/
        vagrant scp $BASEDIR/kon $(ssh::host):~/
        vagrant scp $KON_PKI_DIR $(ssh::host):~/pki
    else
        scp $active_config $(ssh::user)$(ssh::host):~/
        scp $BASEDIR/kon $(ssh::user)$(ssh::host):~/
        scp $KON_PKI_DIR $(ssh::user)$(ssh::host):~/pki
    fi
}

ssh::install_kon () {
    if [ "$KON_DEV" == "true" ]; then
            $(ssh::cmd) << EOF
sudo /kon-dev/update-all.sh \
&& sudo mv ~/pki /etc/kon/ \
&& sudo mv /etc/kon/pki/consul-*.crt /etc/kon/pki/consul.crt \
&& sudo mv /etc/kon/pki/consul-*.csr /etc/kon/pki/consul.csr \
&& sudo mv /etc/kon/pki/consul-*.key /etc/kon/pki/consul.key
EOF
    else
    $(ssh::cmd) << EOF
sudo mkdir -p /opt/bin \
&& sudo mv ~/kon /opt/bin \
&& sudo chmod a+x /opt/bin/kon \
&& sudo mkdir -p /etc/kon \
&& sudo cp ~/kon.conf /etc/kon/ \
&& sudo mv ~/pki /etc/kon/ \
&& sudo mv /etc/kon/pki/consul-*.crt /etc/kon/pki/consul.crt \
&& sudo mv /etc/kon/pki/consul-*.csr /etc/kon/pki/consul.csr \
&& sudo mv /etc/kon/pki/consul-*.key /etc/kon/pki/consul.key 
EOF
    fi
}

ssh::setup_node () {
    $(ssh::cmd) << EOF
sudo /opt/bin/kon setup node
EOF
}
