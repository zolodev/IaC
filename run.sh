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
    echo "  prep              Install Ansible and create vault.yml + prod.ini (run first)"
    echo "  prep --reset      Regenerate vault.yml and .vault_pass (new secrets)"
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

VAULT_FILE="$PWD/group_vars/all/vault.yml"
INVENTORY="$PWD/prod.ini"
TARGET="$1"

case "$TARGET" in
    prep)
        RESET=false
        if [[ "${2:-}" == "--reset" ]]; then
            RESET=true
            echo "  --reset: existing vault.yml and .vault_pass will be replaced"
            echo ""
            rm -f "$VAULT_FILE" "$PWD/.vault_pass"
        fi

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

        # ── 2. Create .vault_pass with generated password if missing ─────────
        if [ ! -f "$PWD/.vault_pass" ]; then
            VAULT_PASS=$(set +o pipefail; cat /dev/urandom | tr -dc 'a-zA-Z0-9!#$%&()*+,-./:<=>?@[\]^_{}~' | head -c 50)
            echo "$VAULT_PASS" > "$PWD/.vault_pass"
            chmod 600 "$PWD/.vault_pass"
            echo "  ✓ .vault_pass generated"
        else
            VAULT_PASS=$(cat "$PWD/.vault_pass")
            echo "  ✓ .vault_pass already exists — skipping"
        fi
        echo ""

        # ── 4. Create vault.yml from example if missing ───────────────────────
        if [ ! -f "$VAULT_FILE" ]; then
            # Exclude \ from Garage secret — TOML double-quoted strings treat it as escape
            GARAGE_RPC=$(set +o pipefail; cat /dev/urandom | tr -dc 'a-zA-Z0-9!#$%&()*+,-./:<=>?@[]^_{}~' | head -c 50)
            cp "$PWD/group_vars/vault.example.yml" "$VAULT_FILE"
            chmod 600 "$VAULT_FILE"
            python3 - "$VAULT_FILE" "$GARAGE_RPC" <<'PYEOF'
import sys
path, val = sys.argv[1], sys.argv[2]
content = open(path).read()
content = content.replace('vault_garage_rpc_secret: ""', f'vault_garage_rpc_secret: "{val}"')
open(path, 'w').write(content)
PYEOF

            echo "┌────────────────────────────────────────────────────────────────────────────┐"
            echo "│  Generated secrets — save these in Bitwarden before continuing             │"
            echo "├────────────────────────────────────────────────────────────────────────────┤"
            printf "│  Vault password:    %-54s │\n" "$VAULT_PASS"
            printf "│  Garage RPC secret: %-54s │\n" "$GARAGE_RPC"
            echo "└────────────────────────────────────────────────────────────────────────────┘"
            echo ""
            echo "Opening vault.yml — fill in vault_k3s_token and vault_become_pass,"
            echo "then save and close."
            echo ""
            "${EDITOR:-nano}" "$VAULT_FILE"

            ansible-vault encrypt "$VAULT_FILE"
            echo "  ✓ vault.yml encrypted"
        else
            echo "  ✓ vault.yml already exists — skipping"
        fi
        echo ""

        # ── 5. Create prod.ini from example if missing ───────────────────────
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
            echo "Error: group_vars/all/vault.yml not found."
            echo "Run './run.sh prep' first."
            exit 1
        fi
        if [ ! -f "$INVENTORY" ]; then
            echo "Error: prod.ini not found."
            echo "Run './run.sh prep' first."
            exit 1
        fi

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
        esac
        ;;

    *)
        echo "Unknown command: $TARGET"
        usage
        exit 1
        ;;
esac
