#!/bin/bash

help_msg () {
  cat <<EOF
Alpha Commands:
  cluster start            Starts all given a kon.conf file.

Setup Commands (high level):
  setup node               Installs and starts all software needed for running Kubernetes on node.
  setup kubectl            Configures kubectl for accessing the cluster.

Generate Commands:
  generate init            Generates a sample /etc/kon.conf file
  generate all             Generates etcd configuration, certificates and kubeconfigs.
  generate etcd            Reads the etcd configuration and stores it in consul.
  generate certificates    Generates all certificates and stores them in consul. The command only generates missing certificates and is safe to be run multiple times.
  generate kubeconfigs     Generates all kubeconfig-files and stores them in consul.

Start Commands:
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

Nomad Commands:
  nomad install            Installs Nomad
  nomad start              Starts Nomad
  nomad restart            Restarts Nomad
  nomad stop               Stops Nomad

Etcd Commands:
  etcd start               Starts the etcd cluster.
  etcd stop                Stopps the etcd cluster.
  etcd reset               Stopps etcd and deletes all configuration.

Kubernetes Commands:
  kubernetes start         Starts all Kubernetes components
  kubernetes install       Installs kubernetes components: kubelet, kubeadm and kubectl
  kubernetes reset         Stopps kubernetes control plane and deletes all certificates and configuration.

Other Commands:
  addon dns                Installs dns addon.
  view status              Shows kon status.

EOF
}

# m4_ignore(
echo "This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  #)Created by argbash-init v2.5.0
# ARG_OPTIONAL_SINGLE([config], c, [Configuration file to use], [])
# ARG_OPTIONAL_BOOLEAN([debug], , [Run kon in debug mode (bash -x)], [off])
# ARG_OPTIONAL_BOOLEAN([quiet], , [Quiet mode, output less], [off])
# ARG_OPTIONAL_BOOLEAN([print], , [A boolean option with long flag (and implicit default: off)])
# ARG_POSITIONAL_MULTI([command], [Positional arg description], [3], [""])
# ARG_HELP([KON helps you setup and run Kubernetes On Nomad (KON).\n], [$(help_msg)])
# ARG_VERSION([echo $(cat $BASEDIR/version)])
# ARGBASH_SET_INDENT([  ])
# ARGBASH_GO

# [ <-- needed because of Argbash

if [ "$_arg_print" = on ]
then
  echo "Command arg value: '${_arg_command[*]}'"
  echo "Optional arg '--config|-c' value: '$_arg_config'"
  echo "Optional arg '--bootstrap|-b' value: '$_arg_bootstrap'"
  echo "Optional arg '--debug' value: '$_arg_debug'"
  echo "Optional arg '--quiet' value: '$_arg_quiet'"
  echo "Optional arg '--interface|-i' value: '$_arg_interface'"
fi

# ] <-- needed because of Argbash
