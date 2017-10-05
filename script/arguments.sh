#!/bin/bash

help_msg () {
  cat <<EOF
Install Commands:
  install consul
  install nomad
  install kube             Installs kubernetes components: kubelet, kubeadm and kubectl

Generate Commands:
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

Other Commands:
  enable dns               Enables service lookup in consul using the hosts resolv.conf.
  addon dns                Installs dns addon.
  setup kubectl            Configures kubectl for accessing the cluster.
  start bootstrap consul
  start consul

EOF
}

# Created by argbash-init v2.5.0
# ARG_OPTIONAL_SINGLE([config],[c],[Configuration file to use],[])
# ARG_OPTIONAL_SINGLE([interface],[i],[Network interface to use for Consul bind address],[])
# ARG_OPTIONAL_SINGLE([bootstrap],[b],[Bootstrap Consul Server],[])
# ARG_OPTIONAL_BOOLEAN([print],[],[A boolean option with long flag (and implicit default: off)])
# ARG_POSITIONAL_MULTI([command],[Positional arg description],[3],[""])
# ARG_HELP([KON helps you setup and run Kubernetes On Nomad (KON).\n],[$(help_msg)])
# ARG_VERSION([echo kon v0.1-alpha])
# ARGBASH_SET_INDENT([  ])
# ARGBASH_GO()
# needed because of Argbash --> m4_ignore([
### START OF CODE GENERATED BY Argbash v2.5.0 one line above ###
# Argbash is a bash code generator used to get arguments parsing right.
# Argbash is FREE SOFTWARE, see https://argbash.io for more info

die()
{
  local _ret=$2
  test -n "$_ret" || _ret=1
  test "$_PRINT_HELP" = yes && print_help >&2
  echo "$1" >&2
  exit ${_ret}
}

begins_with_short_option()
{
  local first_option all_short_options
  all_short_options='cibhv'
  first_option="${1:0:1}"
  test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}



# THE DEFAULTS INITIALIZATION - POSITIONALS
_positionals=()
_arg_command=('' '' "")
# THE DEFAULTS INITIALIZATION - OPTIONALS
_arg_config=
_arg_interface=
_arg_bootstrap=
_arg_print=off

print_help ()
{
  printf "%s\n" "KON helps you setup and run Kubernetes On Nomad (KON).
		"
  printf 'Usage: %s [-c|--config <arg>] [-i|--interface <arg>] [-b|--bootstrap <arg>] [--(no-)print] [-h|--help] [-v|--version] <command-1> <command-2> [<command-3>]\n' "$0"
  printf "\t%s\n" "<command>: Positional arg description (defaults for <command-3>: '""')"
  printf "\t%s\n" "-c,--config: Configuration file to use (no default)"
  printf "\t%s\n" "-i,--interface: Network interface to use for Consul bind address (no default)"
  printf "\t%s\n" "-b,--bootstrap: Bootstrap Consul Server (no default)"
  printf "\t%s\n" "--print,--no-print: A boolean option with long flag (and implicit default: off) (off by default)"
  printf "\t%s\n" "-h,--help: Prints help"
  printf "\t%s\n" "-v,--version: Prints version"
  printf "\n%s\n" "$(help_msg)"
}

parse_commandline ()
{
  while test $# -gt 0
  do
    _key="$1"
    case "$_key" in
      -c|--config)
        test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
        _arg_config="$2"
        shift
        ;;
      --config=*)
        _arg_config="${_key##--config=}"
        ;;
      -c*)
        _arg_config="${_key##-c}"
        ;;
      -i|--interface)
        test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
        _arg_interface="$2"
        shift
        ;;
      --interface=*)
        _arg_interface="${_key##--interface=}"
        ;;
      -i*)
        _arg_interface="${_key##-i}"
        ;;
      -b|--bootstrap)
        test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
        _arg_bootstrap="$2"
        shift
        ;;
      --bootstrap=*)
        _arg_bootstrap="${_key##--bootstrap=}"
        ;;
      -b*)
        _arg_bootstrap="${_key##-b}"
        ;;
      --no-print|--print)
        _arg_print="on"
        test "${1:0:5}" = "--no-" && _arg_print="off"
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      -h*)
        print_help
        exit 0
        ;;
      -v|--version)
        echo kon v0.1-alpha
        exit 0
        ;;
      -v*)
        echo kon v0.1-alpha
        exit 0
        ;;
      *)
        _positionals+=("$1")
        ;;
    esac
    shift
  done
}


handle_passed_args_count ()
{
  _required_args_string="'command' (2 times)"
  test ${#_positionals[@]} -lt 2 && _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require between 2 and 3 (namely: $_required_args_string), but got only ${#_positionals[@]}." 1
  test ${#_positionals[@]} -gt 3 && _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect between 2 and 3 (namely: $_required_args_string), but got ${#_positionals[@]} (the last one was: '${_positionals[*]: -1}')." 1
}

assign_positional_args ()
{
  _positional_names=('_arg_command[0]' '_arg_command[1]' '_arg_command[2]' )

  for (( ii = 0; ii < ${#_positionals[@]}; ii++))
  do
    eval "${_positional_names[ii]}=\${_positionals[ii]}" || die "Error during argument parsing, possibly an Argbash bug." 1
  done
}

# OTHER STUFF GENERATED BY Argbash

### END OF CODE GENERATED BY Argbash (sortof) ### ])
# [ <-- needed because of Argbash


if [ "$_arg_print" = on ]
then
  echo "Command arg value: '${_arg_command[*]}'"
  echo "Optional arg '--config|-c' value: '$_arg_config'"
  echo "Optional arg '--bootstrap|-b' value: '$_arg_bootstrap'"
else
  echo "Not telling anything, print not requested"
fi

# ] <-- needed because of Argbash
