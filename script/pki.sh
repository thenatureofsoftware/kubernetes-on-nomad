#!/bin/bash

pki::install () {
    wget --quiet -O cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    chmod a+x cfssl
    mv cfssl $BINDIR
}

pki::generate_ca () {
    if [ ! $(common::which cfssl) ]; then fail "cfssl not found, please install it"; fi
    if [ "$KON_PKI_DIR" == "" ]; then fail "KON_PKI_DIR is not set, is KON_CONFIG loaded?"; fi
    if [ -f "$KON_PKI_DIR/ca.crt" ]; then info "CA certificate already present, nothing to do"; fi
    ca_json=$(echo '{"key": {"algo":"rsa","size":2048},"CN":"kubernetes-on-nomad"}' | cfssl -loglevel 5 genkey -initca=true -)
    echo $ca_json | jq -r .csr > $KON_PKI_DIR/ca.csr
    echo $ca_json | jq -r .cert > $KON_PKI_DIR/ca.crt
    echo $ca_json | jq -r .key > $KON_PKI_DIR/ca.key
}

pki::generate_consul_cert () {
    if [ ! $(common::which cfssl) ]; then fail "cfssl not found, please install it"; fi
    if [ ! -f "$KON_PKI_DIR/ca.key" ]; then info "ca key is missing"; fi
    if [ ! -f "$KON_PKI_DIR/ca.crt" ]; then info "ca certificate is missing"; fi
    cert_json=$(pki::generate_consul_config $1 | cfssl -loglevel 5 gencert -ca $KON_PKI_DIR/ca.crt -ca-key $KON_PKI_DIR/ca.key -hostname=$1 -)
    echo $cert_json | jq -r .csr > $KON_PKI_DIR/consul-$1.csr
    echo $cert_json | jq -r .cert > $KON_PKI_DIR/consul-$1.crt
    echo $cert_json | jq -r .key > $KON_PKI_DIR/consul-$1.key
}

pki::clean_up_certs () {
    if [ "$1" == "" ]; then return 0; fi
    info "Cleaning up certificates for $1"
    rm $KON_PKI_DIR/consul-$1.*
}

pki::generate_consul_config () {
    cat <<EOF
{
    "usages": ["signing", "key encipherment", "server auth", "client auth"],
    "CN": "$1",
    "key": {
        "algo": "rsa",
        "size": 2048
    }
}
EOF
}

pki::check_ca () {
    pki::check_ca_cert
    pki::check_ca_key
}

pki::check_ca_cert () {
    pki::check_cert "ca"
}

pki::check_ca_key () {
    pki::check_key "ca"
}

pki::check_consul () {
    pki::check_cert "consul"
    pki::check_key "consul"
}

pki::check_nomad () {
    pki::check_cert "nomad"
    pki::check_key "nomad"
}

pki::check_cert () {
    if [ ! -f $KON_PKI_DIR/$1.crt ]; then fail "no $1 cert"; fi
}

pki::check_key () {
    if [ ! -f $KON_PKI_DIR/$1.key ]; then fail "no $1 key"; fi
}
