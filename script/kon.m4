#!/bin/bash

help_msg () {
  cat <<EOF
Install Commands:
  install nomad
  install kube             Installs kubernetes components: kubelet, kubeadm and kubectl

Generate Commands:
  generate init            Generates a sample /etc/kon.conf file
  generate all             Generates certificates and kubeconfigs.
  generate etcd            Reads the etcd configuration and stores it in consul.
  generate certificates    Generates all certificates and stores them in consul. The command only generates missing certificates and is safe to be run multiple times.
  generate kubeconfigs     Generates all kubeconfig-files and stores them in consul.

Start Commands:
  start all
  start etcd
  start kubelet
  start kube-proxy
  start control-plane

Reset Commands:
  reset all                Stopps all running jobs and deletes all certificates and configuration.
  reset etcd               Stopps etcd and deletes all configuration.
  reset kubernetes         Stopps kubernetes control plane and deletes all certificates and configuration.

Consul Commands:
  consul install           Installs Consul
  consul start             Starts Consul, --bootstrap and --interface arguments are required
  consul start bootstrap   Starts a bootstrap Consul, --interface argument are required 
  consul dns enable        Enables all DNS lookups through Consul
  consul dns disable       Disables all DNS lookups through Consul and restores the original config

Other Commands:
  consul dns enable        Enables all DNS lookups through Consul
  consul dns disable       Disables all DNS lookups through Consul and restores the original config
  addon dns                Installs dns addon.
  setup kubectl            Configures kubectl for accessing the cluster.
  start bootstrap consul
  start consul

EOF
}

# m4_ignore(
echo "This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  #)Created by argbash-init v2.5.0
# ARG_OPTIONAL_SINGLE([config], c, [Configuration file to use], [])
# ARG_OPTIONAL_SINGLE([interface], i, [Network interface to use for Consul bind address], [])
# ARG_OPTIONAL_SINGLE([bootstrap], b, [Bootstrap Consul Server], [])
# ARG_OPTIONAL_BOOLEAN([print], , [A boolean option with long flag (and implicit default: off)])
# ARG_POSITIONAL_MULTI([command], [Positional arg description], [3], [""])
# ARG_HELP([KON helps you setup and run Kubernetes On Nomad (KON).\n], [$(help_msg)])
# ARG_VERSION([echo kon v0.1-alpha])
# ARGBASH_SET_INDENT([  ])
# ARGBASH_GO

# [ <-- needed because of Argbash

if [ "$_arg_print" = on ]
then
  echo "Command arg value: '${_arg_command[*]}'"
  echo "Optional arg '--config|-c' value: '$_arg_config'"
  echo "Optional arg '--bootstrap|-b' value: '$_arg_bootstrap'"
  echo "Optional arg '--interface|-i' value: '$_arg_interface'"
fi

# ] <-- needed because of Argbash
