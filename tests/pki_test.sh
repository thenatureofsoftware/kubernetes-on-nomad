#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::pki::"

KON_SERVERS=swe:swe-east:core-01:172.17.4.101,swe:swe-west:core-02:172.17.4.102,swe:swe-north:core-03:172.17.4.103,us:east::172.17.4.104
KON_MINIONS=swe:swe-east:core-05:172.17.4.105,swe:swe-west:core-06:172.17.4.106,swe:swe-north:core-07:172.17.4.107,us:us-east:core-08:172.17.4.108


test::pki::setup () {
    KON_PKI_DIR=$(mktemp -d)
}

test::pki::tear_down () {
    rm -rf $KON_PKI_DIR
}

test::pki::generate_ca () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
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

test::pki::generate_name () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh

    config::nodes
    assert "generate_name" "$(pki::generate_name consul '172.17.4.101')" "server.swe-east.consul"
}

test::pki::generate_consul_cert () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh

    config::nodes
    pki::generate_ca

    pki::generate_consul_cert "172.17.4.101"
    assert "generate_consul_cert_server_crt" "$(test -f $KON_PKI_DIR/server.swe-east.consul.crt; echo "$?")" "0"
    assert "generate_consul_cert_server_key" "$(test -f $KON_PKI_DIR/server.swe-east.consul.key; echo "$?")" "0"
    assert "generate_consul_cert_server_csf" "$(test -f $KON_PKI_DIR/server.swe-east.consul.csr; echo "$?")" "0"

    pki::generate_consul_cert "172.17.4.108"
    assert "generate_consul_cert_client_crt" "$(test -f $KON_PKI_DIR/core-08.us-east.consul.crt; echo "$?")" "0"
    assert "generate_consul_cert_client_key" "$(test -f $KON_PKI_DIR/core-08.us-east.consul.key; echo "$?")" "0"
    assert "generate_consul_cert_client_csf" "$(test -f $KON_PKI_DIR/core-08.us-east.consul.csr; echo "$?")" "0"
}

test::pki::generate_nomad_cert () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh

    config::nodes
    pki::generate_ca

    pki::generate_nomad_cert "172.17.4.101"
    assert "generate_nomad_cert_server_crt" "$(test -f $KON_PKI_DIR/server.swe.nomad.crt; echo "$?")" "0"
    assert "generate_nomad_cert_server_key" "$(test -f $KON_PKI_DIR/server.swe.nomad.key; echo "$?")" "0"
    assert "generate_nomad_cert_server_csf" "$(test -f $KON_PKI_DIR/server.swe.nomad.csr; echo "$?")" "0"

    pki::generate_nomad_cert "172.17.4.108"
    assert "generate_nomad_cert_client_crt" "$(test -f $KON_PKI_DIR/client.us.nomad.crt; echo "$?")" "0"
    assert "generate_nomad_cert_client_key" "$(test -f $KON_PKI_DIR/client.us.nomad.key; echo "$?")" "0"
    assert "generate_nomad_cert_client_csf" "$(test -f $KON_PKI_DIR/client.us.nomad.csr; echo "$?")" "0"
}

test::pki::generate_csr () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh

    assert "generate_csr" "$(pki::generate_csr server.east.consul | jq -r .CN)" "server.east.consul"
}

trap test::pki::tear_down EXIT

test::pki::setup
(test::pki::generate_ca)
(test::pki::generate_name)
(test::pki::generate_csr)
(test::pki::generate_consul_cert)
(test::pki::generate_nomad_cert)
