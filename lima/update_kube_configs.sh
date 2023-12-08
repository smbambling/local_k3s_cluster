#!/usr/bin/env bash
#
# shellcheck disable=SC1091
source "$(dirname -- "$( readlink -f -- "$0"; )")/../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "awk"
  "yq"
  "limactl"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

dotdir="${HOME}/.kube"
mkdir -p "${dotdir}"

# fetch the localk3sclusten kubeconfig file
if ! output=$(limactl shell localk3sserver1 cat /etc/rancher/k3s/k3s.yaml > "${dotdir}"/localk3s 2>&1); then
  echo "failed to update the localk3s kubeconf"
  echo "${output}"
  exit 1
fi

# update the clusters.cluster.server address for localk3sserver
localk3sserver_ip=$(limactl shell localk3sserver1 ip -4 -o addr show lima0 | awk '{ print $4}' | awk -F/ '{print $1}')
yq -i ".clusters.[].cluster.server= \"https://${localk3sserver_ip}:6443\"" "${dotdir}"/localk3s

# set secure permissions
chmod 600 "${dotdir}"/localk3s
