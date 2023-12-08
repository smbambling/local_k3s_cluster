#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $0

Examples:

$0 -c 1 -m 4 -d 20  --- set the CPU, Memory and Disk values
$0 -v v1.27.3+k3s1  --- set the K3s install version
$0 -t server        --- set the K3s cluster type
$0 -s 3             --- set the K3s cluster s

Where:
  -c VM CPU count
  -d VM Disk size in GiB
  -h Help/Usage
  -m VM memory size in GiB
  -s K3s cluster size (total node count)
  -t K3s cluster type multi-(agent[default]/server)
  -v K3s install version
EOF
   exit 1
}

# set default values
vm_cpus="1"
vm_memory="4"
vm_disk="20"
k3s_version="v1.27.3+k3s1"
k3s_cluster_type="agent"
k3s_cluster_size=3

while getopts "c:d:hm:s:t:v:" arg; do
  case "${arg}" in
    c)
      vm_cpus=${OPTARG} ;;
    d)
      vm_disk=${OPTARG} ;;
    h)
      usage ;;
    m)
      vm_memory=${OPTARG} ;;
    s)
      k3s_cluster_size=${OPTARG} ;;
    t)
      k3s_cluster_type=${OPTARG} ;;
    v)
      k3s_version=${OPTARG} ;;
    *)
      usage ;;
  esac
done

if [[ "${k3s_cluster_type}" != "agent" && "${k3s_cluster_type}" != "server" ]]; then
  echo "Aborting: Incorrect value for arg: -t supplied. Valid values are [ agent or server ]"
  exit 1
fi

if ! [[ "${k3s_cluster_size}" =~ ^[0-9]+$ ]]; then
  echo "Aborting: Expected arguemnt to be an integer value for arg: -s (cluster size)"
  exit 1
fi

# set script_dir location
script_dir=$(dirname -- "$( readlink -f -- "$0"; )")

if [[ "${k3s_cluster_type}" == *"server"* ]]; then
  node_seq_start="2"
  node_seq_end="${k3s_cluster_size}"
  lima_initial_template="${script_dir}/localk3scluster.yaml"
  lima_subsequent_template="${script_dir}/localk3scluster.yaml"
  echo "********************************************************************"
  echo "Creating a multi-node cluster with ${node_seq_end} server ( control-plane/etcd ) nodes"
  echo -e "********************************************************************\n"
else
  node_seq_start="1"
  # subtract 1 from the total number of nodes from $1 argument input
  node_seq_end="$((k3s_cluster_size-1))"
  lima_initial_template="${script_dir}/localk3sserver.yaml"
  lima_subsequent_template="${script_dir}/localk3sagent.yaml"
  echo "*********************************************************************************"
  echo "Creating a multi-node cluster with 1 server ( control-plane/etcd ) and ${node_seq_end} agent nodes "
  echo -e "*********************************************************************************\n"
fi

# shellcheck disable=SC1091
source "${script_dir}/../../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "yq"
  "limactl"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

# check if a localk3s single-node cluster exists
if limactl list --log-level error | grep -qe 'localk3sserver1'; then
  if ! limactl list --log-level error | grep -qe 'localk3sserver2\|localk3sserver3\|localk3sagent'; then
      echo "Aborting: A single-node localk3s cluster currently exits"
      echo "Please destroy the current localk3s cluster and re-run"
      exit 1
  elif [ "${k3s_cluster_type}" == "server" ]; then
    # check to see if a cluster with agent nodes exists
    if limactl list --log-level error | grep -qe "localk3sagent"; then
      echo "Aborting: A multi-node cluster with a single ( control-plane/etcd ) server and agent nodes exists"
      echo "Please destroy the current localk3s cluster and re-run"
      exit 1
    fi
  elif [ "${k3s_cluster_type}" == "agent" ]; then
    # check to see if a cluster with multiple server ( control-plane/etcd ) nodes exists
    if limactl list --log-level error | grep -qe "localk3sserverm2\|localk3sserver3"; then
      echo "Aborting: A multi-node cluster with multiple ( control-plane/etcd ) server nodes exists"
      echo "Please destroy the current localk3s cluster and re-run"
      exit 1
    fi
  fi
fi

# check if localk3sserver1 vm instance is created
if limactl list --log-level error | grep -q localk3sserver1; then
  # check if localk3sserver1 vm instance is started
  localk3sserver_state=$(limactl list -f yaml | yq '.| select(.instance.name == "localk3sserver1")| .instance.status')

  echo "Starting localk3sserver1 vm instance: "
  # start spinnger to show status
  start_spinner
  if [ "${localk3sserver_state}" != "Running" ]; then
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
  echo "Creating localk3sserver1 vm instance: "
  # start spinnger to show status
  start_spinner
  if ! output=$(limactl start --name=localk3sserver1 --set=".cpus = ${vm_cpus} | .memory = \"${vm_memory}GiB\" | .disk = \"${vm_disk}GiB\" | .env.INSTALL_K3S_VERSION = \"${k3s_version}\"" --tty=false "${lima_initial_template}" 2>&1); then
    stop_spinner
    echo "Failed to start localk3sserver1 vm instance"
    echo "${output}"
    exit 1
  fi
  # stop the spinner
  stop_spinner
  echo -e "...Completed"
fi

#################################################
###### K3s Additional Server / Agent Nodes ######
#################################################

# get localk3sserver IP address
localk3sserver_ip=$(limactl shell localk3sserver1 ip -4 -o addr show lima0 | awk '{ print $4}' | awk -F/ '{print $1}')

# get/set K3S server variable values
K3S_TOKEN=$(limactl shell localk3sserver1 sudo cat /var/lib/rancher/k3s/server/node-token)
K3S_URL="https://${localk3sserver_ip}:6443"

for i in $(seq "${node_seq_start}" "${node_seq_end}"); do
  if limactl list --log-level error | grep -q "localk3s${k3s_cluster_type}${i}"; then
    localk3sserver_state=$(limactl list -f yaml | yq ".| select(.instance.name == \"localk3s${k3s_cluster_type}${i}\")| .instance.status")

    echo "Starting localk3s${k3s_cluster_type}${i} vm instance: "
    # start spinnger to show status
    start_spinner
    if [ "${localk3sserver_state}" != "Running" ]; then
      if ! output=$(limactl start "localk3s${k3s_cluster_type}${i}" --tty=false 2>&1); then
        stop_spinner
        echo "Failed to start localk3s${k3s_cluster_type}${i} vm instance..."
        echo "${output}"
        exit 1
      fi
    fi
    # stop the spinner
    stop_spinner
    echo -e "...Completed"
  else
    echo "Creating localk3s${k3s_cluster_type}${i} vm instance: "
    # start spinnger to show status
    start_spinner
    if ! output=$(bash -c "limactl start --name=localk3s${k3s_cluster_type}${i} --set='.cpus = ${vm_cpus} | .memory = \"${vm_memory}GiB\" | .disk = \"${vm_disk}GiB\" | .env.INSTALL_K3S_VERSION = \"${k3s_version}\" | .env.K3S_TOKEN = \"${K3S_TOKEN}\" | .env.K3S_URL = \"${K3S_URL}\"' --tty=false ${lima_subsequent_template}" 2>&1); then
      stop_spinner
      echo "Failed to start localk3s${k3s_cluster_type}${i} vm instance"
      echo "${output}"
      exit 1
    fi
    # stop the spinner
    stop_spinner
    echo -e "...Completed"
  fi
done

# the node-role agent label needs to be set manually
# Reference: https://github.com/k3s-io/k3s/issues/1289
# where @ is an arbitrary placeholder symbol that xargs will use to inject the ouput from grep, one line at a time (-n1)
for node in $(limactl shell localk3sserver1 kubectl get nodes -o name | grep 'localk3sagent'); do
  if ! output=$(xargs -n1 -I@ limactl shell localk3sserver1 kubectl label @ node-role.kubernetes.io/agent=true <<< "${node}" 2>&1); then
    echo "Failed to add label node-role.kubernetes.io to localk3sagent${i}"
    echo "${output}"
  else
    echo "Added label node-role.kubernetes.io to localk3sagent${i}"
  fi
done

################################
###### local host updates ######
################################

# fetch the cluster kubeconfig
echo "Updating localk3s kube configs: "
"${script_dir}"/../update_kube_configs.sh
echo -e "...Completed"

# update /etc/hosts value for name based access
echo "Updating /etc/host entires"
"${script_dir}"/../update_etc_hosts.sh
echo -e "...Completed"
