#!/bin/bash

common::install () {
    info "installing json2hcl ..."
    wget --quiet https://github.com/kvz/json2hcl/releases/download/v0.0.6/json2hcl_v0.0.6_linux_amd64
    mv json2hcl_v0.0.6_linux_amd64 /opt/bin/json2hcl
    chmoad a+x /opt/bin/json2hcl
    json2hcl --version > "$(common::dev_null)" 2>&1
    if [ $? -gt 0 ]; then fail "json2hcl install failed"; fi
    info "json2hcl installed"
}