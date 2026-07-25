#!/bin/bash
# run.sh — run the right playbook with local inventory
#
# prod.ini lives locally on zh and is gitignored (*.ini).
# Copy inventory/hosts.example.ini as a template and adapt.
#
# Usage:
#   ./run.sh                  # run setup-homelab (default)
#   ./run.sh homelab          # run setup-homelab
#   ./run.sh zh               # run setup-zh
#   ./run.sh base             # apt security updates on all nodes
#   ./run.sh prep             # prepare the Ansible control host

set -euo pipefail

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

    cat > "$VAULT_FILE" <<EOF
---
# Auto-generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by run.sh
# Encrypt before use: ansible-vault encrypt group_vars/vault.yml

vault_k3s_token: "$K3S_TOKEN"
vault_garage_rpc_secret: "$GARAGE_RPC"
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

# ── Local inventory with real IPs — never committed to git ───────────────────
if [ ! -f "$PWD/prod.ini" ]; then
    echo "ERROR: prod.ini not found — create it from inventory/hosts.example.ini"
    echo "  cp inventory/hosts.example.ini prod.ini"
    echo "  # fill in real IPs and hostnames"
    exit 1
fi

INVENTORY="$PWD/prod.ini"
TARGET="${1:-homelab}"

case "$TARGET" in
    homelab)
        ansible-playbook playbooks/setup-homelab.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    zh)
        ansible-playbook playbooks/setup-zh.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    base)
        ansible-playbook playbooks/apt.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    prep)
        ansible-playbook playbooks/prep_ansible_host.yml -i "$INVENTORY" "${VAULT_ARGS[@]}" "${@:2}"
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: ./run.sh [homelab|zh|base|prep]"
        exit 1
        ;;
esac
