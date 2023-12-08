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
  k3s_cluster_init="--cluster-init"
  echo "********************************************************************"
  echo "Creating a multi-node cluster with ${node_seq_end} server ( control-plane/etcd ) nodes"
  echo -e "********************************************************************\n"
else
  node_seq_start="1"
  # subtract 1 from the total number of nodes from $1 argument input
  node_seq_end="$((k3s_cluster_size-1))"
  echo "*********************************************************************************"
  echo "Creating a multi-node cluster with 1 server ( control-plane/etcd ) and ${node_seq_end} agent nodes "
  echo -e "*********************************************************************************\n"
fi

# shellcheck disable=SC1091
source "${script_dir}/../../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "yq"
  "multipass"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

# check if a localk3s single-node cluster exists
if multipass list | grep -qe 'localk3sserver1'; then
  if ! multipass list | grep -qe 'localk3sserverm2\|localk3sserver3\|localk3sagent'; then
    echo "Aborting: A single-node localk3s cluster currently exits"
    echo "Please destroy the current localk3s cluster and re-run"
    exit 1
  elif [ "${k3s_cluster_type}" == "server" ]; then
    # check to see if a cluster with agent nodes exists
    if multipass list | grep -qe "localk3sagent"; then
      echo "Aborting: A multi-node cluster with a single ( control-plane/etcd ) server and agent nodes exists"
      echo "Please destroy the current localk3s cluster and re-run"
      exit 1
    fi
  elif [ "${k3s_cluster_type}" == "agent" ]; then
    # check to see if a cluster with multiple server ( control-plane/etcd ) nodes exists
    if multipass list | grep -qe "localk3sserverm2\|localk3sserver3"; then
      echo "Aborting: A multi-node cluster with multiple ( control-plane/etcd ) server nodes exists"
      echo "Please destroy the current localk3s cluster and re-run"
      exit 1
    fi
  fi
fi

# get localk3sserver1 vm instance info
localk3sserver1_status=$(multipass list --format yaml | yq '.localk3sserver1')

# check if localk3sserver1 vm instance is created
if [[ "${localk3sserver1_status}" != "null" ]]; then
  echo "Starting localk3sserver1 vm instance: "
  # check localk3sserver1 vm instance is started
  localk3sserver1_state=$(multipass info localk3sserver1 --format yaml | yq '.localk3sserver1.[].state')

  if [ "${localk3sserver1_state}" != "Running" ]; then
    # start localk3sserver1 vm instance
    multipass start localk3sserver1
    echo "Waiting for localk3sserver1 vm instance to start"
    sleep 10

    n=1
    until [ $n -ge 16 ]; do
      localk3sserver1_state=$(multipass info localk3sserver1 --format yaml | yq '.localk3sserver1.[].state')
      if [ "${localk3sserver1_state}" != "Running" ]; then
        echo "Still waiting for localk3sserver1 vm instance to fully start"
        echo "  Checking again in 10s"
        n=$((n + 1))
        sleep 10
      else
        break
      fi
    done
  fi
  echo -e "...Completed"
else
  # launch localk3sserver1 instance
  echo "Creating localk3sserver1 vm instance: "
  multipass launch 22.04 \
    --name localk3sserver1 \
    --cpus "${vm_cpus}" \
    --memory "${vm_memory}G" \
    --disk "${vm_disk}G" \
    --cloud-init "${script_dir}"/localk3s-init.yaml

  # gather localk3sserver1 information
  server1_ext_ip=$(multipass info localk3sserver1 --format yaml | yq '.localk3sserver1.[].ipv4.[0]')
  server1_ext_intface=$(multipass exec localk3sserver1 ip addr | awk -v myip="${server1_ext_ip}" '$0 ~ myip { print $NF }')

  # Create K3s config.yaml
  multipass exec localk3sserver1 -- sudo bash -c "cat << EOF > /etc/rancher/k3s/config.yaml
---
write-kubeconfig-mode: \"0644\"
disable:
  - traefik
  - servicelb
# disable-network-policy: true
secrets-encryption: true
#system-default-registry: myLocalRegistry
kube-controller-manager-arg:
  - \"bind-address=0.0.0.0\"
kube-proxy-arg:
  - \"metrics-bind-address=0.0.0.0\"
kube-scheduler-arg:
  - \"bind-address=0.0.0.0\"
node-ip: \"${server1_ext_ip}\"
tls-san:
  - localk3sserver1
EOF"

  echo "Installing K3s on localk3sserver1"
  # Initialize the cluster on localk3sserver1
  if ! output=$(multipass exec localk3sserver1 -- bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=mylocalk3stoken \
  INSTALL_K3S_VERSION=\"${k3s_version}\" sh -s server \"${k3s_cluster_init}\" \
  --node-external-ip=\"${server1_ext_ip}\" --flannel-external-ip \
  --flannel-iface=\"${server1_ext_intface}\" --bind-address=\"${server1_ext_ip}\"" 2>&1); then
    echo "Failed to install/start K3s on localk3sserver1"
    echo "${output}"
  else
    echo "Successfull installed and started K3s on localk3sserver1"
  fi
fi

#################################################
###### K3s Additional Server / Agent Nodes ######
#################################################

localk3sserver_ip=$(multipass info localk3sserver1 --format yaml | yq '.localk3sserver1.[].ipv4.[0]')

# get/set K3S server variable values
K3S_TOKEN=$(multipass exec localk3sserver1 sudo cat /var/lib/rancher/k3s/server/node-token)
K3S_URL="https://${localk3sserver_ip}:6443"

for i in $(seq "${node_seq_start}" "${node_seq_end}"); do
  localk3sserver_status=$(multipass list --format yaml | yq ".localk3s${k3s_cluster_type}${i}")
  if [[ "${localk3sserver_status}" != "null" ]]; then
    echo "Starting localk3s${k3s_cluster_type}${i} vm instance: "
    # check localk3s vm instance is started
    localk3sserver_state=$(multipass info "localk3s${k3s_cluster_type}${i}" --format yaml | yq ".localk3s${k3s_cluster_type}${i}.[].state")

    if [ "${localk3sserver_state}" != "Running" ]; then
      # start localk3sserver vm instance
      multipass start "localk3s${k3s_cluster_type}${i}"
      echo "Waiting for localk3s vm instance to start"
      sleep 10

      n=1
      until [ $n -ge 16 ]; do
        localk3sserver_state=$(multipass info "localk3s${k3s_cluster_type}${i}" --format yaml | yq ".localk3s${k3s_cluster_type}${i}.[].state")
        if [ "${localk3sserver_state}" != "Running" ]; then
          echo "Still waiting for localk3s${k3s_cluster_type}${i} vm instance to fully start"
          echo "  Checking again in 10s"
          n=$((n + 1))
          sleep 10
        else
          break
        fi
      done
    fi
    echo -e "...Completed"
  else
    echo "Creating localk3s${k3s_cluster_type}${i} vm instance: "
    # launch localk3s instance
    multipass launch 22.04 \
      --name "localk3s${k3s_cluster_type}${i}" \
      --cpus "${vm_cpus}" \
      --memory "${vm_memory}G" \
      --disk "${vm_disk}G" \
      --cloud-init "${script_dir}"/localk3s-init.yaml

    # gather localk3sserver1 information
    server_ext_ip=$(multipass info "localk3s${k3s_cluster_type}${i}" --format yaml | yq ".localk3s${k3s_cluster_type}${i}.[].ipv4.[0]")
    server_ext_intface=$(multipass exec "localk3s${k3s_cluster_type}${i}" ip addr | awk -v myip="${server_ext_ip}" '$0 ~ myip { print $NF }')

    if [[ "${k3s_cluster_type}" == *"server"* ]]; then
      multipass exec "localk3s${k3s_cluster_type}${i}" -- sudo mkdir -p /etc/rancher/k3s

      # Create K3s config.yaml
      multipass exec "localk3s${k3s_cluster_type}${i}" -- sudo bash -c "cat << EOF > /etc/rancher/k3s/config.yaml
---
write-kubeconfig-mode: \"0644\"
disable:
  - traefik
  - servicelb
# disable-network-policy: true
secrets-encryption: true
#system-default-registry: myLocalRegistry
kube-controller-manager-arg:
  - \"bind-address=0.0.0.0\"
kube-proxy-arg:
  - \"metrics-bind-address=0.0.0.0\"
kube-scheduler-arg:
  - \"bind-address=0.0.0.0\"
node-ip: \"${server_ext_ip}\"
tls-san:
  - localk3s${k3s_cluster_type}${i}
EOF"

      echo "Installing K3s on localk3s${k3s_cluster_type}${i}"
      # Initialize the cluster on localk3sserver1
      if ! output=$(multipass exec "localk3s${k3s_cluster_type}${i}" -- bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=\"${K3S_TOKEN}\" \
      K3S_URL=\"${K3S_URL}\" INSTALL_K3S_VERSION=\"${k3s_version}\" sh -s server \
      --node-external-ip=\"${server_ext_ip}\" --flannel-external-ip \
      --flannel-iface=\"${server_ext_intface}\" --bind-address=\"${server_ext_ip}\"" 2>&1); then
        echo "Failed to install/start K3s on localk3s${k3s_cluster_type}${i}"
        echo "${output}"
      else
        echo "Successfull installed and started K3s on localk3s${k3s_cluster_type}${i}"
      fi
    else
      multipass exec "localk3s${k3s_cluster_type}${i}" -- sudo mkdir -p /etc/rancher/k3s

      # Create K3s config.yaml
      multipass exec "localk3s${k3s_cluster_type}${i}" -- sudo bash -c "cat << EOF > /etc/rancher/k3s/config.yaml
---
node-ip: \"${server_ext_ip}\"
EOF"

      echo "Installing K3s on localk3s${k3s_cluster_type}${i}..."
      if ! output=$(multipass exec "localk3s${k3s_cluster_type}${i}" -- bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=\"${K3S_TOKEN}\" \
      K3S_URL=\"${K3S_URL}\" INSTALL_K3S_VERSION=v1.27.3+k3s1 sh -s agent \
      --node-external-ip=\"${server_ext_ip}\" --flannel-iface=\"${server_ext_intface}\"" 2>&1); then
        echo "Failed to install/start K3s on localk3s${k3s_cluster_type}${i}"
        echo "${output}"
      else
        echo "Successfull installed and started K3s on localk3s${k3s_cluster_type}${i}"
      fi
    fi
  fi
done

for node in $(multipass exec localk3sserver1 -- kubectl get nodes -o name | grep 'localk3sagent'); do
  if ! output=$(xargs -n1 -I@ multipass exec localk3sserver1 -- kubectl label @ node-role.kubernetes.io/agent=true <<< "${node}" 2>&1); then
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
