#!/usr/bin/env bash

# Function to check if referenced command exists
check_required_cmds() {
  if [ -z "${1}" ]; then
    echo "command list not passed"
    return 1
  fi
  cmd_list=${1}

  # shellcheck disable=SC2034
  local cmd_exists

  cmd_exists() {
    if [ $# -eq 0 ]; then
      echo 'WARNING: No command argument was passed to verify exists'
    fi
    # shellcheck disable=SC2207
    cmds=($(printf '%s' "${1}"))
    fail_counter=0
    for cmd in "${cmds[@]}"; do
      if ! command -v "${cmd}" >&/dev/null; then  # portable 'which'
        fail_counter=$((fail_counter+1))
      fi
    done

    if [ "${fail_counter}" -ge "${#cmds[@]}" ]; then
      echo "Unable to find one of the required commands [${cmds[*]}] in your PATH"
      exit 1
    fi
  }

  # Verify that referenced commands exist on the system
  for cmd in "${cmd_list[@]}"; do
    if ! cmd_exists "${cmd[@]}"; then
      exit 1
    fi
  done
}

spinner_pid=

function start_spinner {
    set +m
    echo -n "$1         "
    { while : ; do for X in '  •     ' '   •    ' '    •   ' '     •  ' '      • ' '     •  ' '    •   ' '   •    ' '  •     ' ' •      ' ; do echo -en "\b\b\b\b\b\b\b\b$X" ; sleep 0.1 ; done ; done & } 2>/dev/null
    spinner_pid=$!
}

function stop_spinner {
    { kill -9 "${spinner_pid}" && wait; } 2>/dev/null
    set -m
    echo -en "\033[2K\r"
}

trap stop_spinner EXIT

function update_etc_host_entries() {
  local kubectlingresses
  kubectlingresses="${1}"

  local kubectlservices
  kubectlservices="${2}"

  # loop over kubectl ingress list output and add /etc/hosts entries
  if [ -n "${kubectlingresses}" ]; then
    echo "The following ingress endpoint entries were updated in /etc/hosts:"
  fi
  while IFS= read -r line; do
    if [ "$line" != "" ]; then
      host=$(awk '{ print $4 }' <<< "${line}")
      addr=$(awk '{ print $5 }' <<< "${line}")
      echo "${host} - ${addr}"
      if ! grep -q "${addr} ${host}" /etc/hosts; then
        sudo bash -c "sed -i '/# begin localk3s kubernetes/a ${addr} ${host}' /etc/hosts"
      fi
    fi
  done <<< "${kubectlingresses}"

  # loop over kubectl service list output and add /etc/hosts entries
  if [ -n "${kubectlservices}" ]; then
    echo -e "\nThe following service endpoint entries were updated in /etc/hosts:"
  fi
  while IFS= read -r line; do
    if [ "$line" != "" ]; then
      host=$(awk '{ print "local-"$2"-svc" }' <<< "${line}")
      addr=$(awk '{ print $5 }' <<< "${line}")
      echo "${host} - ${addr}"
      if ! grep -q "${addr} ${host}" /etc/hosts; then
        sudo bash -c "sed -i '/# begin localk3s kubernetes/a ${addr} ${host}' /etc/hosts"
      fi
    fi
  done <<< "${kubectlservices}"
}
