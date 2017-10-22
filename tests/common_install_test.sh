#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::common_install::"

test::test::common_install::setup_suite () {
    KON_BIN_DIR=$(mktemp -d)
}

test::test::common_install::setup_test () {
    rm -f $KON_BIN_DIR/*
    if [ ! "$(echo $PATH | grep $KON_BIN_DIR)" ]; then PATH=$KON_BIN_DIR:$PATH; fi
    _arg_yes=on

}

test::common_install::tear_down () {
    rm -rf $KON_BIN_DIR
}

test::common_install::cfssl () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/common_install.sh


    test::test::common_install::setup_test
    _test_="Darwin X86_64"
    common_install::cfssl
    assert "cfssl" "$(common::which cfssl)" "$KON_BIN_DIR/cfssl"

    test::test::common_install::setup_test
    _test_="Linux X86_64"
    common_install::cfssl
    assert "cfssl" "$(common::which cfssl)" "$KON_BIN_DIR/cfssl"
}

trap test::common_install::tear_down EXIT


test::test::common_install::setup_suite
(test::common_install::cfssl)
