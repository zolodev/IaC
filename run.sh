#!/bin/bash
# run.sh — run one or more playbooks with local inventory
#
# Usage:
#   ./run.sh prep              # install Ansible and create config files (first time)
#   ./run.sh homelab           # full home lab setup
#   ./run.sh zh                # set up zh node only
#   ./run.sh apt                # refresh apt cache on all nodes (add --tags upgrade to upgrade)
#   ./run.sh timezone          # set timezone (run separately, can reboot)
#   ./run.sh homelab apt       # run multiple playbooks in sequence
#   ./run.sh --help            # show this help

set -euo pipefail

usage() {
    echo ""
    echo "Usage: ./run.sh <command> [<command> ...] [ansible-options]"
    echo ""
    echo "Commands:"
    echo "  prep              Install Ansible and create vault.yml + prod.ini (run first)"
    echo "  prep --reset      Regenerate vault.yml and .vault_pass (new secrets)"
    echo "  homelab    Full home lab setup (packages, k3s, add-ons)"
    echo "  zh         Set up zh node only"
    echo "  apt        Refresh apt cache on all nodes (--tags upgrade to also upgrade)"
    echo "  timezone   Set timezone on all nodes (run separately, can reboot)"
    echo ""
    echo "Multiple commands run their playbooks in sequence, each as its own"
    echo "ansible-playbook invocation — nothing is combined via ansible tags."
    echo ""
    echo "Any arguments after the command(s) are passed through to every"
    echo "ansible-playbook invocation."
    echo "Examples:"
    echo "  ./run.sh homelab --tags k3s"
    echo "  ./run.sh homelab --limit jetson --check"
    echo "  ./run.sh timezone --limit jetson --tags reboot"
    echo "  ./run.sh apt --tags upgrade"
    echo "  ./run.sh homelab apt --limit jetson"
    echo ""
}

if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

export ANSIBLE_CONFIG=$PWD/ansible.cfg

VAULT_FILE="$PWD/group_vars/all/vault.yml"
INVENTORY="$PWD/prod.ini"

playbook_file() {
    case "$1" in
        homelab)  echo "playbooks/setup-homelab.yml" ;;
        zh)       echo "playbooks/setup-zh.yml" ;;
        apt)      echo "playbooks/apt.yml" ;;
        timezone) echo "playbooks/timezone.yml" ;;
        *)        return 1 ;;
    esac
}

if [[ "$1" == "prep" ]]; then
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
fi

# ── Guard: require vault.yml and prod.ini ─────────────────────────────────
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

# ── Collect one or more playbook names, then pass the rest through ────────
PLAYBOOKS=()
while [[ $# -gt 0 && "$1" != -* ]]; do
    if ! FILE=$(playbook_file "$1"); then
        echo "Unknown command: $1"
        usage
        exit 1
    fi
    PLAYBOOKS+=("$FILE")
    shift
done

if [[ ${#PLAYBOOKS[@]} -eq 0 ]]; then
    echo "No command given."
    usage
    exit 1
fi

for PB in "${PLAYBOOKS[@]}"; do
    echo "── ansible-playbook $PB ──"
    ansible-playbook "$PB" -i "$INVENTORY" "$@"
done
