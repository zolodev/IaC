#!/bin/bash
# run.sh — run the right playbook with local inventory
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

VAULT_FILE="$PWD/group_vars/vault.yml"
INVENTORY="$PWD/prod.ini"
TARGET="$1"

case "$TARGET" in
    prep)
        # ── 1. Install Ansible if missing ────────────────────────────────────
        if ! command -v ansible-playbook &>/dev/null; then
            echo "Ansible not found — installing..."
            sudo apt-get update -qq
            sudo apt-get install -y ansible
            echo "  ✓ Ansible installed ($(ansible --version | head -1))"
        else
            echo "  ✓ Ansible already installed ($(ansible --version | head -1))"
        fi
        echo ""

        # ── 2. Create vault.yml from example if missing ───────────────────────
        if [ ! -f "$VAULT_FILE" ]; then
            cp "$PWD/group_vars/vault.example.yml" "$VAULT_FILE"
            chmod 600 "$VAULT_FILE"
            echo "Opening vault.yml — fill in your secrets, then save and close."
            echo ""
            "${EDITOR:-nano}" "$VAULT_FILE"

            echo ""
            if [ -f "$PWD/.vault_pass" ]; then
                ansible-vault encrypt --vault-password-file "$PWD/.vault_pass" "$VAULT_FILE"
                echo "  ✓ vault.yml encrypted with existing .vault_pass"
            else
                read -rp "  Encrypt vault.yml with ansible-vault? [Y/n] " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    read -rsp "  Vault password: " vpass; echo ""
                    echo "$vpass" > "$PWD/.vault_pass"
                    chmod 600 "$PWD/.vault_pass"
                    ansible-vault encrypt --vault-password-file "$PWD/.vault_pass" "$VAULT_FILE"
                    echo "  ✓ vault.yml encrypted, password saved to .vault_pass"
                else
                    echo "  Skipped — vault.yml is unencrypted (do not share or commit)"
                fi
            fi
        else
            echo "  ✓ vault.yml already exists — skipping"
        fi
        echo ""

        # ── 3. Create prod.ini from example if missing ────────────────────────
        if [ ! -f "$INVENTORY" ]; then
            cp "$PWD/inventory/hosts.example.ini" "$INVENTORY"
            echo "Opening prod.ini — fill in your host IPs, then save and close."
            echo ""
            "${EDITOR:-nano}" "$INVENTORY"
            echo "  ✓ prod.ini created"
        else
            echo "  ✓ prod.ini already exists — skipping"
        fi
        echo ""

        echo "Setup complete. Run: ./run.sh homelab"
        exit 0
        ;;

    homelab|zh|base)
        # ── Guard: require vault.yml and prod.ini ─────────────────────────────
        if [ ! -f "$VAULT_FILE" ]; then
            echo "Error: group_vars/vault.yml not found."
            echo "Run './run.sh prep' first."
            exit 1
        fi
        if [ ! -f "$INVENTORY" ]; then
            echo "Error: prod.ini not found."
            echo "Run './run.sh prep' first."
            exit 1
        fi

        # ── Pass vault password file if it exists ─────────────────────────────
        VAULT_ARGS=()
        if [ -f "$PWD/.vault_pass" ]; then
            VAULT_ARGS=(--vault-password-file "$PWD/.vault_pass")
        fi

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
        esac
        ;;

    *)
        echo "Unknown command: $TARGET"
        usage
        exit 1
        ;;
esac
