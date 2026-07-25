#!/bin/bash
# run.sh — run the right playbook with local inventory
#
# prod.ini lives locally on zh and is gitignored (*.ini).
# Copy inventory/hosts.example.yml as a template and adapt.
#
# Usage:
#   ./run.sh                  # run setup-homelab (default)
#   ./run.sh homelab          # run setup-homelab
#   ./run.sh zh               # run setup-zh
#   ./run.sh base             # apt security updates on all nodes
#   ./run.sh prep             # prepare the Ansible control host

export ANSIBLE_CONFIG=$PWD/ansible.cfg

# Local inventory with real IPs — never committed to git
if [ -f "$PWD/prod.ini" ]; then
    INVENTORY="$PWD/prod.ini"
else
    echo "ERROR: prod.ini not found — create it from inventory/hosts.example.yml"
    echo "  cp inventory/hosts.example.yml prod.ini"
    echo "  # fill in real IPs and hostnames"
    exit 1
fi

TARGET="${1:-homelab}"

case "$TARGET" in
    homelab)
        ansible-playbook playbooks/setup-homelab.yml -i "$INVENTORY" "${@:2}"
        ;;
    zh)
        ansible-playbook playbooks/setup-zh.yml -i "$INVENTORY" "${@:2}"
        ;;
    base)
        ansible-playbook playbooks/apt.yml -i "$INVENTORY" "${@:2}"
        ;;
    prep)
        ansible-playbook playbooks/prep_ansible_host.yml -i "$INVENTORY" "${@:2}"
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: ./run.sh [homelab|zh|base|prep]"
        exit 1
        ;;
esac
