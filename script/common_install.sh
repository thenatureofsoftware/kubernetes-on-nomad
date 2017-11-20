#!/bin/bash

###############################################################################
# Install cfssl
###############################################################################
common_install::cfssl () {
    common::mk_bindir

    if [ ! "$_test_" ] && [ "$(common::which cfssl)" ]; then
        return 0
    fi

    shall_we=$(common_install::ask_if_we_should_install "cfssl")
    if [ ! "$shall_we" == "true" ]; then
        fail "cfssl 1.2.0 is required for creating certificates, you can download and install it from https://pkg.cfssl.org"
    fi

    os="$(common::system_info | jq -r .os)"
    arch="$(common::system_info | jq -r .arch)"
    echo "Install for $os $arch"

    if [ ! -d "$KON_BIN_DIR" ]; then fail "$KON_BIN_DIR no such directory"; return 1; fi
    if [ "$arch" == "arm64" ] || [ "$arch" == "arm" ]; then
        curl -sSL -o $KON_BIN_DIR/cfssl https://pkg.cfssl.org/R1.2/cfssl_$os-arm
    else
        curl -sSL -o $KON_BIN_DIR/cfssl https://pkg.cfssl.org/R1.2/cfssl_$os-$arch
    fi
    chmod +x $KON_BIN_DIR/cfssl
}

###############################################################################
# Ask user if he/she want's to install binary
# Param #1 - the binary to ask for
# Param #2 - if it's required
# Param #3 - fail message if the user answers anything but yes
###############################################################################
common_install::ask_if_we_should_install () {
    binary_to_ask_for=$1
    if [ ! "$(common::which $binary_to_ask_for)" ] || [ "$_test_" ]; then
        if [ ! "$_arg_yes" ] || [ "$_arg_yes" == "off" ]; then
            read -p "$binary_to_ask_for is not installed, do you want to download and install? (y) [y/Y] " install
        else
            install="y"
        fi

        if [ ! "$install" == "" ] && [ ! "${install,,}" == "y" ]; then
            echo "false"
        fi

        echo "true"
    fi
}