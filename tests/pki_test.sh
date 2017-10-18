#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::pki::"


test::pki::setup () {
    KON_PKI_DIR=$(mktemp -d)
}

test::pki::tear_down () {
    rm -rf $KON_PKI_DIR
}

test::pki::generate_ca () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/pki.sh
    
    pki::generate_ca

    assert "generate_ca_crt" "$(test -f $KON_PKI_DIR/ca.crt; echo "$?")" "0"
    assert "generate_ca_key" "$(test -f $KON_PKI_DIR/ca.key; echo "$?")" "0"
    assert "generate_ca_csr" "$(test -f $KON_PKI_DIR/ca.csr; echo "$?")" "0"

    NO_LOG=false
    out=$(pki::generate_ca)
    assert "generate_ca_nothing_to_do" "${out:27}" "CA certificate already present, nothing to do"
    NO_LOG=true
}

test::pki::generate_consul_cert () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/pki.sh

    server="server.east.consul"
    pki::generate_ca
    pki::generate_consul_cert server.east.consul $server

    assert "generate_consul_cert_crt" "$(test -f $KON_PKI_DIR/consul-$server.crt; echo "$?")" "0"
    assert "generate_consul_cert_crt" "$(test -f $KON_PKI_DIR/consul-$server.key; echo "$?")" "0"
    assert "generate_consul_cert_crt" "$(test -f $KON_PKI_DIR/consul-$server.csr; echo "$?")" "0"
}

test::pki::generate_consul_config () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/pki.sh

    assert "generate_consul_config" "$(pki::generate_consul_config server.east.consul | jq -r .CN)" "server.east.consul"
}

trap test::pki::tear_down EXIT

test::pki::setup
(test::pki::generate_ca)
(test::pki::generate_consul_config)
(test::pki::generate_consul_cert)
