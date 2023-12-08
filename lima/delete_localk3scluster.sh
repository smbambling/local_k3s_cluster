#!/usr/bin/env bash

# ask for sudo password up front
if ! sudo -n true 2>/dev/null; then
  echo "Enter your local sudo password"
  sudo -v
fi

# delete all localserver* vm instances
for node in $(limactl list | awk '/localk3s/ { print $1 }'); do
  limactl delete "${node}" -f
done

# clear all entires in the section block
sudo sed -i '/begin localk3s kubernetes/,/end localk3s kubernetes/{/begin localk3s kubernetes/n;/end localk3s kubernetes/!d;}' /etc/hosts
