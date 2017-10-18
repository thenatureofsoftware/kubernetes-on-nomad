#!/bin/bash

# bash -c 'source script/common.sh; source script/config.sh; config::get_region'

declare -A config_nodes
declare -A config_regions
# config_minions[<IP-address]=<hostname>
declare -A config_minions
config_bootstrap_server=""

###############################################################################
# Returns true or false if the IP-address is included in KON_SERVERS
# Param: $1 IP-address (optional)
###############################################################################
config::is_server () {
    if [ ! "$1" == "" ]; then
        ip_address="$1"
    else
        ip_address="$(common::ip_addr)"
    fi

    if [ "$(echo $KON_SERVERS | grep $ip_address)" == "" ]; then
        echo "false"
    else
        echo "true"
    fi
}

###############################################################################
# Returns the hostname for a server given it's IP-address.
# Param: $1 IP-address
###############################################################################
config::get_host () {
  
  ip_addr="$1"
  
  hostname=$(config::get_meta_info $1| awk -F ':' '{print $1}')
  
  if [ "$hostname" == "" ]; then fail "hostname not found for IP-address: $ip_addr"; fi
  echo $hostname
}

###############################################################################
# Returns the region for a server given it's IP-address.
# Param: $1 IP-address
###############################################################################
config::get_region () {
  
  ip_addr="$1"
  
  region=$(config::get_meta_info $1| awk -F ':' '{print $2}')
  
  if [ "$region" == "" ]; then fail "region not found for IP-address: $ip_addr"; fi
  echo $region
}

###############################################################################
# Returns the datacenter for a server given it's IP-address.
# Param: $1 IP-address
###############################################################################
config::get_dc () {
  
  ip_addr="$1"
  
  datacenter=$(config::get_meta_info $1 | awk -F ':' '{print $3}')
  
  if [ "$datacenter" == "" ]; then fail "datacenter not found for IP-address: $ip_addr"; fi
  echo $datacenter
}

###############################################################################
# Returns the meta info (<hostname>:<region>:<datacenter>) for a server given
# it's IP-address.
# Param: $1 IP-address
###############################################################################
config::get_meta_info () {
  
  ip_addr="$1"
  if [ "$ip_addr" == "" ]; then
    ip_addr="$(common::ip_addr)"
  fi

  if [ "$KON_SERVERS" == "" ]; then fail "KON_SERVERS is empty, is KON_CONFIG loaded?"; fi
  if [ "$ip_addr" == "" ]; then fail "ip address required"; fi

  meta_info=${config_nodes[$ip_addr]}
  if [ "$meta_info" == "" ]; then fail "meta info not found for IP-address: $ip_addr"; fi
  echo $meta_info
}

###############################################################################
# Populates an associative array of all kon nodes.
# config_nodes[<IP-address>]=<hostname>:<region>:<datacenter>
###############################################################################
config::nodes () {

  if [ "$KON_SERVERS" == "" ]; then fail "KON_SERVERS is empty, is KON_CONFIG loaded?"; fi
  
  IFS=$' '
  read -r -a servers <<< "$(echo $KON_SERVERS | sed 's/ //g' | sed 's/,/ /g')"
  
  for server in ${servers[@]}; do
    local ip_address="$(config::node_ip $server)"
    local meta_info="$(config::node_meta $server)"
    config_nodes[$ip_address]=$meta_info
  done

  config::bootstrap_server

  if [ "$KON_MINIONS" == "" ]; then fail "KON_MINIONS is empty, is KON_CONFIG loaded?"; fi

  IFS=$' '
  read -r -a servers <<< "$(echo $KON_MINIONS | sed 's/ //g' | sed 's/,/ /g')"
  unset IFS
  
  for server in ${servers[@]}; do
    local ip_address="$(config::node_ip $server)"
    local meta_info="$(config::node_meta $server)"
    config_nodes[$ip_address]=$meta_info
    config_minions[$ip_address]="$(echo $meta_info | awk -F ':' '{print $1}')"
  done
}

###############################################################################
# Populates an associative array of all regions and datacenters
# config_regions[<rerion>]=<datacenter1>:<datacenter2>:<datacenter3>
###############################################################################
config::regions () {
  for node in ${!config_nodes[@]}; do
    region=$(config::get_region $node)
    if [ ! ${config_regions[$region]+_} ]; then
      config_regions[$region]=$(config::datacenters_for "$region")
    fi
  done
}

###############################################################################
# Returns all datacenters for a given region by looping through all nodes.
# Param $1 region
###############################################################################
config::datacenters_for () {
  declare -A dc
  for node in ${!config_nodes[@]}; do
    if [ "$(config::get_region $node)" == "$1" ]; then dc[$(config::get_dc $node)]=""; fi
  done
  echo ${!dc[@]}
}

###############################################################################
# Checks that datacenters are unique over all regions.
# It makes no sense to have to datacenters named dc1 in two different regions.
###############################################################################
config::check_unique_dc () {
  declare -A dc_set
  for datacenters in ${config_regions[@]}; do
    for dc in "$datacenters"; do
      if [ ! ${dc_set[$dc]+_} ]; then
        dc_set[$dc]=""
      else
        fail "found multiple datacenters named: $dc in different regions, datacenter names must be globaly unique"
      fi
    done
  done
}

###############################################################################
# Returns all datacenters for a region
# Param $1 region
###############################################################################
function config::datacenters () {
  local datacenters=${config_regions[$1]}
  echo $(common::join_by ", " ${config_regions[$1]}| sed s/,/\",\"/g)
}

###############################################################################
# Configures a nomad job with region and datacenters.
# Param $1 region
# stdin nomad job cat <nomad job> | config:configure_job swe | nomad run -
###############################################################################
function config::configure_job () {
  sed 's/"global"/"'"$1"'"/' | sed 's/"dc1"/"'"$(config::datacenters $1)"'"/'
}

###############################################################################
# Returns the IP-address of the bootstrap server.
###############################################################################
config::bootstrap_server () {

  if [ ! "$_arg_bootstrap" == "" ]; then
    KON_BOOTSTRAP_SERVER=$_arg_bootstrap
  fi

  if [ "$KON_BOOTSTRAP_SERVER" == "" ]; then
    fail "no bootstrap server configured, is KON_CONFIG loaded?"
  fi

  config_bootstrap_server=$KON_BOOTSTRAP_SERVER
}

###############################################################################
# Returns the region part of a server config:
# <region>:<datacenter>:<hostname>:<IP-address>
# Param $1 a server config
###############################################################################
function config::node_region () {
  s_conf=$(config::node_param_check $1)
  echo $s_conf | awk -F ':' '{print $1}'
}

###############################################################################
# Returns the datacenter part of a server config:
# <region>:<datacenter>:<hostname>:<IP-address>
# Param $1 a server config
###############################################################################
function config::node_dc () {
  s_conf=$(config::node_param_check $1)
  echo $s_conf | awk -F ':' '{print $2}'
}

###############################################################################
# Returns the hostname part of a server config:
# <region>:<datacenter>:<hostname>:<IP-address>
# Param $1 a server config
###############################################################################
function config::node_hostname () {
  s_conf=$(config::node_param_check $1)
  echo $s_conf | awk -F ':' '{print $3}'
}

###############################################################################
# Returns the IP-address part of a server config:
# <region>:<datacenter>:<hostname>:<IP-address>
# Param $1 a server config
###############################################################################
function config::node_ip () {
  s_conf=$(config::node_param_check $1)
  echo $s_conf | awk -F ':' '{print $4}'
}

###############################################################################
# Returns the meta-info of a server config:
# <region>:<datacenter>:<hostname>:<IP-address>
# Param $1 a server config
###############################################################################
function config::node_meta () {
  s_conf=$(config::node_param_check $1)
  echo $s_conf | awk -F ':' '{print $3 ":" $1 ":" $2}'
}

function config::node_param_check () {
  echo $1
  if [ ! "$1" ]; then fail "a server entry (<region>:<datacenter>:<hostname>:<IP-address>) is required"; fi
}

###############################################################################
# Loads configuration file                                                    #
###############################################################################
config::configure () {

  avtive_config=""

  if [ "$_arg_config" ] && [ -f "$_arg_config" ]; then
      active_config=$_arg_config
  elif [ -f "$KON_CONFIG" ]; then
      active_config=$KON_CONFIG
  elif [ ! "$(common::which consul)" == "" ] && [ $(docker ps -q -f "name=kon-consul") ] && touch $KON_CONFIG > $(common::dev_null) 2>&1; then
      mkdir -p $KON_INSTALL_DIR
      consul::get $konConfigKey > $KON_CONFIG 2>&1
      if [ $? -eq 0 ]; then
          active_config=$KON_CONFIG
      else
          rm -f $KON_CONFIG
      fi
  fi

  if [ -f "$active_config" ]; then
      source $active_config
      info "read configuration from $active_config"

      if [ "$KON_SAMPLE_CONFIG" == "true" ]; then
          fail "can't use a sample configuration, please edit $active_config first"
      fi

      if [ -f "$KON_CONFIG" ]; then
          if [ ! "$(common::which consul)" == "" ] && [ $(docker ps -q -f "name=kon-consul") ]; then
            consul::put_file $konConfig $KON_CONFIG > "$(common::dev_null)" 2>&1
            if [ $? -eq 0 ]; then consul::put $configStateKey $OK; fi
          fi
      fi
      config::nodes
      config::regions
  fi
}

###############################################################################
# Genetares the config template for KON.
###############################################################################
config::generate_config_template () {
  info "generating sample configuration file $KON_CONFIG"
  mkdir -p $KON_INSTALL_DIR
  cat <<EOF > $KON_CONFIG
#!/bin/bash

###############################################################################
# Kubernetes version
###############################################################################
K8S_VERSION=${K8S_VERSION:=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}
CNI_VERSION=${CNI_VERSION:=v0.6.0}

###############################################################################
# Cluster command settings
# These settings is only used by the cluster command.
###############################################################################
# If your ssh command requires a username.
# KON_SSH_USER=core
# Set this to true if your doing vagrant ssh.
KON_VAGRANT_SSH=false

###############################################################################
# kubeadm version
###############################################################################
KUBEADM_VERSION=${KUBEADM_VERSION:=v1.9.0-alpha.1}

###############################################################################
# Consul Bootstrap server
###############################################################################
KON_BOOTSTRAP_SERVER=192.168.1.101
KON_BIND_INTERFACE=enp0s8

###############################################################################
# List of Consul and Nomad servers
# <region>:<datacenter>:<hostname>:<ip addr>
###############################################################################
KON_SERVERS=swe:east:core-01:172.17.4.101,swe:west:core-02:172.17.4.102,swe:north:core-03:172.17.4.103

###############################################################################
# List of comma separated addresses <scheme>://<ip>:<port>
###############################################################################
ETCD_SERVERS=http://etcd.service.dc1.consul:2379

###############################################################################
# List of etcd initial cluster <name>=<scheme>://<ip>:<port>
###############################################################################
ETCD_INITIAL_CLUSTER=default=http://127.0.0.1:2380

###############################################################################
# Etcd initial cluster token
###############################################################################
ETCD_INITIAL_CLUSTER_TOKEN=etcd-initial-token-dc1

###############################################################################
# List of minions (kubernetes nodes). Must be nomad nodes with node_class
# containing kubelet. Exampel : node_class = "etcd,kubelet"
# <region>:<datacenter>:<hostname>:<ip addr>
###############################################################################
KON_MINIONS=swe:east:node1:192.168.100.101,swe:east:node2:192.168.100.102

###############################################################################
# kube-apiserver advertise address
###############################################################################
KUBE_APISERVER_PORT=6443
KUBE_APISERVER_EXTRA_SANS=kubernetes.service.dc1.consul,kubernetes.service.dc1,kubernetes.service
KUBE_APISERVER_ADDRESS=https://kubernetes.service.east.consul:6443

# Weave
#POD_CLUSTER_CIDR=10.32.0.0/16
# Flannel
POD_CLUSTER_CIDR=10.244.0.0/16

###############################################################################
# Remove this variable or set it to false when done configuring.
###############################################################################
KON_SAMPLE_CONFIG=true

EOF
}
