#!/bin/bash
# run.sh — run the right playbook with local inventory
#
# prod.ini lives locally and is gitignored (*.ini).
# Copy inventory/hosts.example.ini as a template and adapt.
#
# Usage:
#   ./run.sh prep             # install Ansible and create config files (first time)
#   ./run.sh homelab          # full home lab setup
#   ./run.sh zh               # set up zh node only
#   ./run.sh base             # apt security updates on all nodes
#   ./run.sh --help           # show this help

set -euo pipefail

usage() {
    echo ""
    echo "Usage: ./run.sh <command> [ansible-options]"
    echo ""
    echo "Commands:"
    echo "  prep       Install Ansible and create vault.yml + prod.ini (run first)"
    echo "  homelab    Full home lab setup (timezone, packages, k3s, add-ons)"
    echo "  zh         Set up zh node only"
    echo "  base       Run apt security updates on all nodes"
    echo ""
    echo "Any extra arguments after the command are passed through to ansible-playbook."
    echo "Examples:"
    echo "  ./run.sh homelab --tags k3s"
    echo "  ./run.sh homelab --limit jetson --check"
    echo ""
}

if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

export ANSIBLE_CONFIG=$PWD/ansible.cfg

# ── Auto-generate vault.yml on first run ─────────────────────────────────────
VAULT_FILE="$PWD/group_vars/vault.yml"

if [ ! -f "$VAULT_FILE" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  First run: group_vars/vault.yml not found                      │"
    echo "│  Generating secrets automatically...                            │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""

    K3S_TOKEN=$(openssl rand -hex 32)
    GARAGE_RPC=$(openssl rand -hex 32)

    read -rsp "  Sudo password for managed nodes: " BECOME_PASS; echo ""

    cat > "$VAULT_FILE" <<EOF
---
# Auto-generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by run.sh

vault_k3s_token: "$K3S_TOKEN"
vault_garage_rpc_secret: "$GARAGE_RPC"
vault_become_pass: "$BECOME_PASS"
EOF
    chmod 600 "$VAULT_FILE"

    echo "  ✓ group_vars/vault.yml created with generated secrets"
    echo ""

    # Encrypt automatically if .vault_pass already exists
    if [ -f "$PWD/.vault_pass" ]; then
        ansible-vault encrypt --vault-password-file "$PWD/.vault_pass" "$VAULT_FILE"
        echo "  ✓ Encrypted with existing .vault_pass"
    else
        echo "  Encrypt now? (recommended — keeps secrets safe if file is ever shared)"
        echo "  The password will be stored in .vault_pass (gitignored)."
        echo ""
        read -rp "  Encrypt with ansible-vault? [Y/n] " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            read -rsp "  Vault password: " vpass; echo ""
            echo "$vpass" > "$PWD/.vault_pass"
            chmod 600 "$PWD/.vault_pass"
            ansible-vault encrypt --vault-password-file "$PWD/.vault_pass" "$VAULT_FILE"
            echo "  ✓ Encrypted and .vault_pass saved"
        else
            echo "  Skipped — vault.yml is unencrypted (safe locally, do not commit)"
        fi
    fi

    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │  Next: fill in your hosts in prod.ini                        │"
    echo "  │    cp inventory/hosts.example.ini prod.ini                   │"
    echo "  │    # edit prod.ini with real IPs and hostnames               │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
fi

# ── Pass vault password file to ansible if it exists ─────────────────────────
VAULT_ARGS=()
if [ -f "$PWD/.vault_pass" ]; then
    VAULT_ARGS=(--vault-password-file "$PWD/.vault_pass")
fi

# ── Create prod.ini from example if missing ───────────────────────────────────
if [ ! -f "$PWD/prod.ini" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  prod.ini not found — creating from hosts.example.ini           │"
    echo "│  Fill in your real IPs, then save and close to continue.        │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    cp "$PWD/inventory/hosts.example.ini" "$PWD/prod.ini"
    "${EDITOR:-nano}" "$PWD/prod.ini"
fi

INVENTORY="$PWD/prod.ini"
TARGET="$1"

case "$TARGET" in
    prep)
        if ! command -v ansible-playbook &>/dev/null; then
            echo "Ansible not found — installing..."
            sudo apt-get update -qq
            sudo apt-get install -y ansible
            echo "  ✓ Ansible installed ($(ansible --version | head -1))"
        else
            echo "  ✓ Ansible already installed ($(ansible --version | head -1))"
        fi
        echo ""
        echo "Setup complete. Next: edit prod.ini with your host IPs, then run:"
        echo "  ./run.sh homelab"
        exit 0
        ;;
    homelab)
        ansible-playbook playbooks/setup-homelab.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    zh)
        ansible-playbook playbooks/setup-zh.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    base)
        ansible-playbook playbooks/apt.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    *)
        echo "Unknown command: $TARGET"
        usage
        exit 1
        ;;
esac
