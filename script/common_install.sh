#!/bin/bash

common::install () {
    log "Installing basic utilities..."
    apt-get update > /dev/null 2>&1
    apt-get install -y unzip gettext wget jq > /dev/null 2>&1
    log "Done installing utilities"
}