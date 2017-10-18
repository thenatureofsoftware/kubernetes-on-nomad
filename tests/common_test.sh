#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::common::"

test::common::check_cmd () {
    source $SCRIPTDIR/common.sh

    assert "check_cmd_exists" "$(common::check_cmd cat)" "" 
    assert "check_cmd_doesn't_exists" "$(common::check_cmd nixpix)" "nixpix not found"
    
    if [ -z "$(common::check_cmd cat)" ]; then
        assert "check_cmd_in_if" "$(common::check_cmd cat)" ""
    else
        assert "check_cmd_in_if" "" "fail, should not be reached"
    fi
}

test::common::logfile () {
    source $SCRIPTDIR/common.sh

    unset KON_LOG_FILE
    unset NO_LOG
    # Write logs to /var/log/kon.log
    assert "logfile_var_log" "$(common::logfile)" "/var/log/kon.log"

    KON_LOG_FILE=$TESTDIR/kon.log
    assert "logfile_logfile" "$(common::logfile)" "$TESTDIR/kon.log"

    # Write logs to /dev/null
    NO_LOG=true
    assert "logfile_dev_null" "$(common::logfile)" "$(common::dev_null)"
}

test::common::which () {
    source $SCRIPTDIR/common.sh

    assert "which_command_installed" "$(common::which cat)" "$(which cat)"
    assert "which_command_not_installed" "$(common::which nixpix)" ""
}

test::common::fail_on_error () {
    source $SCRIPTDIR/common.sh
    _test_=true

    msg="Failed to list files with -J option"
    ls -J > /dev/null 2>&1
    actual=$(common::fail_on_error "$msg")
    assert "fail_on_error" "$actual" "$(fail "$msg")"

    ls -J > /dev/null 2>&1
    actual=$(common::fail_on_error)
    assert "fail_on_error_no_message" "$actual" "$(fail "A command returned non-zero exit: 1")"

    ls > /dev/null 2>&1
    actual=$(common::fail_on_error)
    assert "fail_on_error_no_failure" "$actual" ""
}

test::common::error_on_error () {
    source $SCRIPTDIR/common.sh

    msg="Failed to list files with -J option"
    ls -J > /dev/null 2>&1
    actual=$(common::error_on_error "$msg")
    assert "error_on_error" "$actual" "$(error "$msg")"

    ls -J > /dev/null 2>&1
    actual=$(common::error_on_error)
    assert "error_on_error_no_message" "$actual" "$(error "A command returned non-zero exit: 1")"

    ls > /dev/null 2>&1
    actual=$(common::error_on_error)
    assert "error_on_error_no_failure" "$actual" ""

    NO_LOG=true
    info "$(ls -J > /dev/null 2>&1)"
    actual=$(common::error_on_error)
    assert "error_on_error_logged_cmd" "$actual" "$(error "A command returned non-zero exit: 1")"
}

test::common::is_bootstrap_server () {
    source $SCRIPTDIR/common.sh
    ip_addr=$(common::ip_addr)

    KON_BOOTSTRAP_SERVER="$ip_addr"
    assert "common::is_bootstrap_server_true" "$(common::is_bootstrap_server)" "true"

    KON_BOOTSTRAP_SERVER="0.0.0.0"
    assert "is_bootstrap_server_false" "$(common::is_bootstrap_server)" "false"
}

(test::common::check_cmd)
(test::common::logfile)
(test::common::which)
(test::common::fail_on_error)
(test::common::error_on_error)
(test::common::is_bootstrap_server)