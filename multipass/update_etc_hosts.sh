#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname -- "$( readlink -f -- "$0"; )")/../common_lib.sh" || exit 255

# command required within the below logic
cmd_list=(
  "awk"
  "multipass"
)

# check if referenced commands exists
check_required_cmds "${cmd_list[@]}"

# ask for sudo password up front
if ! sudo -n true 2>/dev/null; then
  echo "Enter your local sudo password"
  sudo -v
fi

# add section block header/footer
if ! grep -q "# begin localk3s kubernetes" /etc/hosts; then
  echo -e "\n# begin localk3s kubernetes" | sudo tee -a /etc/hosts >/dev/null
  echo -e "\n# end localk3s kubernetes" | sudo tee -a /etc/hosts >/dev/null
fi

# clear all entires in the section block
sudo sed -i '/begin localk3s kubernetes/,/end localk3s kubernetes/{/begin localk3s kubernetes/n;/end localk3s kubernetes/!d;}' /etc/hosts

# get list of ingresses from localk3server1 cluster
kubectlingresses=$(multipass exec localk3sserver1 -- kubectl get ingress -A --no-headers --ignore-not-found=true)
kubectlservices=$(multipass exec localk3sserver1 -- kubectl get svc -A --no-headers | awk '$5 !~ /<none>/ {print}')

# update /etc/hosts entries to add ingress and service endpoints
update_etc_host_entries "${kubectlingresses}" "${kubectlservices}"
