#!/usr/bin/env bash

# ask for sudo password up front
if ! sudo -n true 2>/dev/null; then
  echo "Enter your local sudo password"
  sudo -v
fi

# delete all localk3s vm instances
for node in $(multipass list | awk '/localk3s/ { print $1 }'); do
  multipass delete --purge "${node}"
done

# clear all entires in the section block
sudo sed -i '/begin localk3s kubernetes/,/end localk3s kubernetes/{/begin localk3s kubernetes/n;/end localk3s kubernetes/!d;}' /etc/hosts
