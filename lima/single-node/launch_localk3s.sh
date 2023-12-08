#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $0

Examples:

$0 -c 1 -m 4 -d 20  --- set the CPU, Memory and Disk values
$0 -v v1.27.3+k3s1  --- set the K3s install version

Where:
  -c VM CPU count
  -d VM Disk size in GiB
  -h Help/Usage
  -m VM memory size in GiB
  -v K3s install version
EOF
   exit 1
}

# set default values
vm_cpus="1"
vm_memory="4"
vm_disk="20"
k3s_version="v1.27.3+k3s1"

while getopts "c:d:hm:v:" arg; do
  case "${arg}" in
    c)
      vm_cpus=${OPTARG} ;;
    d)
      vm_disk=${OPTARG} ;;
    h)
      usage ;;
    m)
      vm_memory=${OPTARG} ;;
    v)
      k3s_version=${OPTARG} ;;
    *)
      usage ;;
  esac
done

# set script_dir location
script_dir=$(dirname -- "$( readlink -f -- "$0"; )")

echo "******************************"
echo "Creating a single node cluster"
echo -e "******************************\n"

# shellcheck disable=SC1091
source "${script_dir}/../../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "yq"
  "limactl"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

# check if a localk3s multi-node cluster exists
if limactl list --log-level error | grep -qe 'localk3sserver2\|localk3sserver3\|localk3sagent'; then
  echo "Aborting: A multi-node localk3s cluster currently exits"
  echo "Please destroy the current localk3s cluster and re-run"
  exit 1
fi

# check if localk3sserver1 vm instance is created
if limactl list --log-level error | grep -q localk3sserver1; then
  # check if localk3sserver1 vm instance is started
  localk3sserver1_state=$(limactl list -f yaml | yq '.| select(.instance.name == "localk3sserver1")| .instance.status')

  echo "Starting localk3sserver1 vm instance: "
  # start spinnger to show status
  start_spinner
  if [ "${localk3sserver1_state}" != "Running" ]; then
    if ! output=$(limactl start localk3sserver1 --tty=false 2>&1); then
      stop_spinner
      echo "Failed to start localk3sserver1 vm instance..."
      echo "${output}"
      exit 1
    fi
  fi
  # stop the spinner
  stop_spinner
  echo -e "...Completed"
else
  echo "Starting localk3sserver1 vm instance: "
  # start spinnger to show status
  start_spinner
  if ! output=$(limactl start --name=localk3sserver1 --set=".cpus = ${vm_cpus} | .memory = \"${vm_memory}GiB\" | .disk = \"${vm_disk}GiB\" | .env.INSTALL_K3S_VERSION = \"${k3s_version}\"" --tty=false "${script_dir}/localk3s.yaml" 2>&1); then
    stop_spinner
    echo "Failed to start localk3sserver1 vm instance"
    echo "${output}"
    exit 1
  fi
  # stop the spinner
  stop_spinner
  echo -e "...Completed"
fi

# fetch the cluster kubeconfig
echo "Updating localk3s kube configs: "
"${script_dir}"/../update_kube_configs.sh
echo -e "...Completed"

# update /etc/hosts value for name based access
echo "Updating /etc/host entires"
"${script_dir}"/../update_etc_hosts.sh
echo -e "...Completed"
