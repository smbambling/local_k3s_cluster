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
  "multipass"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

# check if a localk3s multi-node cluster exists
if multipass list | grep -qe 'localk3sserver2\|localk3sserver3\|localk3sagent'; then
  echo "Aborting: A multi-node localk3s cluster currently exits"
  echo "Please destroy the current localk3s cluster and re-run"
  exit 1
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
  multipass launch 22.04 \
    --name localk3sserver1 \
    --cpus "${vm_cpus}" \
    --memory "${vm_memory}G" \
    --disk "${vm_disk}G" \
    --cloud-init "${script_dir}/localk3s-init.yaml"

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
  INSTALL_K3S_VERSION=\"${k3s_version}\" sh -s server \
  --node-external-ip=\"${server1_ext_ip}\" --flannel-external-ip \
  --flannel-iface=\"${server1_ext_intface}\" --bind-address=\"${server1_ext_ip}\"" 2>&1); then
    echo "Failed to install/start K3s on localk3sserver1"
    echo "${output}"
  else
    echo "Successfull installed and started K3s on localk3sserver1"
  fi
fi

# fetch the cluster kubeconfig
echo "Updating localk3s kube configs: "
"${script_dir}"/../update_kube_configs.sh
echo -e "...Completed"

# update /etc/hosts value for name based access
echo "Updating /etc/host entires"
"${script_dir}/../update_etc_hosts.sh"
echo -e "...Completed"
