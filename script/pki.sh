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
    ca_json=$(pki::ca_csr | cfssl -loglevel 5 genkey -initca -)
    #ca_json=$(cfssl print-defaults csr | cfssl gencert -initca -)
    echo $ca_json | jq -r .csr > $KON_PKI_DIR/ca.csr
    echo $ca_json | jq -r .cert > $KON_PKI_DIR/ca.crt
    echo $ca_json | jq -r .key > $KON_PKI_DIR/ca.key
}

pki::generate_client_cert () {
    node=$1
    if [ ! "$node" ]; then fail "node is missing"; fi
    pki::generate_certificate "$(config::get_host $node)" "$(config::get_host $node),$node"
}

pki::generate_consul_cert () {
    node=$1
    if [ ! "$node" ]; then fail "node is missing"; fi
    pki::generate_cert "$(pki::generate_name "consul" $node)" "$node"
}

pki::generate_nomad_cert () {
    node=$1
    if [ ! "$node" ]; then fail "node is missing"; fi
    pki::generate_cert "$(pki::generate_name "nomad" $node)" "$node"
}

pki::generate_cert () {
    cert_bundle_name=$1
    ip_addr=$2

    # Checks
    if [ ! "$cert_bundle_name" ]; then fail "cert bundle name is missing"; fi
    if [ ! "$ip_addr" ]; then fail "node IP-address is missing"; fi
    if [ ! -f "$KON_PKI_DIR/cfssl.json" ]; then pki::generate_cfssl_config; fi
    if [ ! $(common::which cfssl) ]; then fail "cfssl not found, please install it"; fi
    pki::check_ca
    
    if [ -f "$KON_PKI_DIR/$cert_bundle_name.crt" ]; then
        info "certificate and key already generated for $cert_bundle_name, moving on"
    else
        info "generating certificate and key  for $cert_bundle_name"
        cert_json=$(pki::generate_csr $cert_bundle_name | cfssl -loglevel 5 gencert -ca=$KON_PKI_DIR/ca.crt -config=$KON_PKI_DIR/cfssl.json -profile=kon -ca-key=$KON_PKI_DIR/ca.key -hostname="$cert_bundle_name,localhost,127.0.0.1" -)
        echo $cert_json | jq -r .csr > $KON_PKI_DIR/$cert_bundle_name.csr
        echo $cert_json | jq -r .cert > $KON_PKI_DIR/$cert_bundle_name.crt
        echo $cert_json | jq -r .key > $KON_PKI_DIR/$cert_bundle_name.key
    fi
}

pki::generate_certificate () {
    cert_bundle_name=$1
    hosts=$2

    # Checks
    if [ ! "$cert_bundle_name" ]; then fail "cert bundle name is missing"; fi
    if [ ! "$hosts" ]; then fail "hosts list is missing"; fi
    if [ ! -f "$KON_PKI_DIR/cfssl.json" ]; then pki::generate_cfssl_config; fi
    if [ ! $(common::which cfssl) ]; then fail "cfssl not found, please install it"; fi
    pki::check_ca
    
    if [ -f "$KON_PKI_DIR/$cert_bundle_name.crt" ]; then
        info "certificate and key already generated for $cert_bundle_name, moving on"
    else
        info "generating certificate and key  for $cert_bundle_name and hosts [$hosts]"
        cert_json=$(pki::generate_csr $cert_bundle_name | cfssl -loglevel 5 gencert -ca=$KON_PKI_DIR/ca.crt -config=$KON_PKI_DIR/cfssl.json -profile=kon -ca-key=$KON_PKI_DIR/ca.key -hostname="$hosts" -)
        echo $cert_json | jq -r .csr > $KON_PKI_DIR/$cert_bundle_name.csr
        echo $cert_json | jq -r .cert > $KON_PKI_DIR/$cert_bundle_name.crt
        echo $cert_json | jq -r .key > $KON_PKI_DIR/$cert_bundle_name.key
    fi
}

pki::generate_name () {
    target=$1
    node=$2
    
    if [ ! "$node" ]; then fail "node is missing"; fi
    if [ "$target" == "nomad" ]; then
        # Nomad bundle name
        if [ "$(config::is_server $node)" == "true" ]; then
            echo "server.$(config::get_region $node).nomad"
        else
            echo "client.$(config::get_region $node).nomad"
        fi
    elif [ "$target" == "consul" ]; then
        # Consul cert bundle name
        if [ "$(config::is_server $node)" == "true" ]; then
            echo "server.$(config::get_dc $node).consul"
        else
            echo "$(config::get_host $node).$(config::get_dc $node).consul"
        fi
    else
        fail "unknown certificate target: $target"
    fi
}

pki::generate_etcd_service_cert() {
    pki::check_ca
    pki::generate_cfssl_config
    info "generating etcd service certificates"
    cert_json=$(echo {} | $KON_BIN_DIR/cfssl -loglevel 5 gencert -ca=$KON_PKI_DIR/ca.crt -config=$KON_PKI_DIR/cfssl.json -profile=kon -ca-key=$KON_PKI_DIR/ca.key -hostname="etcd.service.consul" -)
    echo $cert_json | jq -r .csr > $KON_PKI_DIR/etcd.service.consul.csr
    echo $cert_json | jq -r .cert > $KON_PKI_DIR/etcd.service.consul.crt
    echo $cert_json | jq -r .key > $KON_PKI_DIR/etcd.service.consul.key
    consul::put_file "$etcdServiceKey/cert" "$KON_PKI_DIR/etcd.service.consul.crt"
    common::fail_on_error "failed to put etcd service cert in consul"
    consul::put_file "$etcdServiceKey/key" "$KON_PKI_DIR/etcd.service.consul.key"
    common::fail_on_error "failed to put etcd service key in consul"
    consul::put_file "$etcdServiceKey/csr" "$KON_PKI_DIR/etcd.service.consul.csr"
    common::fail_on_error "failed to put etcd service csr in consul"
}

pki::generate_csr () {
    if [ ! -f "$KON_CONFIG_DIR/cfssl-config.json" ]; then pki::generate_cfssl_config; fi
    cat <<EOF
{}
EOF
}

pki::generate_cfssl_config () {
    if [ -f "$KON_PKI_DIR/cfssl.json" ]; then return 0; fi
    info "generating kon cfssl config"
    cat <<EOF > $KON_PKI_DIR/cfssl.json
{
    "signing": {
        "profiles": {
            "kon": {
                "expiry": "8760h",
                "key": {
                    "algo": "rsa",
                    "size": 2048
                },
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
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
    ip_addr="$(common::ip_addr)"
    cert_bundle_name="$(pki::generate_name "consul" "$ip_addr")"
    pki::check_cert "$cert_bundle_name"
    pki::check_key "$cert_bundle_name"
}

pki::check_nomad () {
    ip_addr="$(common::ip_addr)"
    cert_bundle_name="$(pki::generate_name "nomad" "$ip_addr")"
    pki::check_cert "$cert_bundle_name"
    pki::check_key "$cert_bundle_name"
}

pki::check_cert () {
    if [ ! -f $KON_PKI_DIR/$1.crt ]; then fail "no $1 cert"; fi
}

pki::check_key () {
    if [ ! -f $KON_PKI_DIR/$1.key ]; then fail "no $1 key"; fi
}

pki::cfssl () {
    docker run --rm -i cfssl/cfssl $*
}

pki::ca_csr () {
    cat <<EOF
{
    "CN": "kubernetes-on-nomad",
    "hosts": [
        "kubernetes-on-nomad.thenatureofsoftware.io"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "O":  "Kubernetes On Nomad",
            "OU": "Cloud"
        }
    ]
}
EOF
}

###############################################################################
# Setup the KON_PKI_DIR for THIS node.
###############################################################################
pki::setup_node_certificates () {
    if [ ! "$(consul::has_key "$konPkiCAKey/cert")" ]; then
        if [ -s "$KON_PKI_DIR/ca.crt" ] && [ -s "$KON_PKI_DIR/ca.key" ]; then
            info "storing kon ca certificate and key in consul"
            consul::put_file "$konPkiCAKey/cert" "$KON_PKI_DIR/ca.crt"
            common::fail_on_error "failed to put ca cert"
            consul::put_file "$konPkiCAKey/key" "$KON_PKI_DIR/ca.key"
            common::fail_on_error "failed to put ca key"
        else
            fail "no ca cert or key"
        fi
    else
        info "fetching kon ca key from consul"
        consul kv get "$konPkiCAKey/key" > "$KON_PKI_DIR/ca.key"
        common::fail_on_error "failed to fetch ca key"
        if [ ! -s "$KON_PKI_DIR/ca.key" ]; then fail "no ca key"; fi
    fi
}
