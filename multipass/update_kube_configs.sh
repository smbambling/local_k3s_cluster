#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname -- "$( readlink -f -- "$0"; )")/../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "yq"
  "multipass"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

dotdir="${HOME}/.kube"
mkdir -p "${dotdir}"

# fetch the localk3sserver1 kubeconfig file
# multipass transfer isn't used because of a bug
# reference: https://github.com/canonical/multipass/issues/1783
if ! output=$(multipass exec localk3sserver1 cat /etc/rancher/k3s/k3s.yaml > "${HOME}"/localk3s 2>&1); then
  echo "failed to update the localk3sserver1 kubeconf"
  echo "${output}"
  exit 1
fi

# update the clusters.cluster.server address for localk3sserver1
localk3sserver1_ip=$(multipass list --format yaml | yq '.localk3sserver1.[].ipv4[0]')
yq -i ".clusters.[].cluster.server= \"https://${localk3sserver1_ip}:6443\"" "${HOME}"/localk3s

# yq via snap doesn't like hidden files
# Re: https://github.com/mikefarah/yq/issues/786
# move localk3s kubeconfig into .arin directory
mv "${HOME}"/localk3s "${dotdir}"/localk3s

# set secure permissions
chmod 600 "${dotdir}"/localk3s
