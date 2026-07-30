#!/bin/bash
# fix-tailscale-routes.sh — re-apply Tailscale subnet route advertisements
#
# k3s's CNI (flannel) brings interfaces up and down on every start AND stop
# of k3s.service — tailscaled treats that as a LinkChange event and clears
# its own AdvertiseRoutes preference in response. Any node with
# tailscale_advertise_routes set in prod.ini can silently drop off the
# tailnet's routing whenever k3s restarts, gets reinstalled, or is stopped
# for troubleshooting — cutting off access to whatever subnet it routes
# (e.g. core-01 -> 192.168.50.0/24, and everything behind it: worker-01/02,
# Proxmox, etc.).
#
# This script re-applies the advertisement unconditionally (idempotent —
# safe to run any time, changes nothing if it's already correct) for every
# host in prod.ini that has tailscale_advertise_routes defined.
#
# Usage:
#   ./fix-tailscale-routes.sh              # fix every host that needs it
#   ./fix-tailscale-routes.sh --dry-run    # show current state only, change nothing

set -euo pipefail

PROD_INI="$(dirname "$0")/prod.ini"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ ! -f "$PROD_INI" ]]; then
    echo "Error: $PROD_INI not found. Run this from the iac repo root." >&2
    exit 1
fi

hosts_found=0

while IFS= read -r line; do
    hosts_found=$((hosts_found + 1))

    alias=$(awk '{print $1}' <<< "$line")
    ansible_host=$(grep -oP 'ansible_host=\K\S+' <<< "$line")
    ansible_user=$(grep -oP 'ansible_user=\K\S+' <<< "$line")
    routes=$(grep -oP 'tailscale_advertise_routes=\K\S+' <<< "$line")

    echo "── $alias ($ansible_host) — should advertise $routes ──"

    get_routes() {
        # Print from the AdvertiseRoutes line up to its closing "]," (a
        # multi-line array) or stop immediately if it's a single-line
        # "null," — either way, without spilling into the next JSON field.
        ssh -o ConnectTimeout=10 "${ansible_user}@${ansible_host}" \
            "sudo tailscale debug prefs 2>/dev/null" \
            | awk '/"AdvertiseRoutes"/{p=1} p{print; if ($0 ~ /null,|\],/) exit}'
    }

    before=$(get_routes)
    echo "  Before: $(tr '\n' ' ' <<< "$before" | xargs)"

    if $DRY_RUN; then
        echo "  (dry run — not changing anything)"
        echo ""
        continue
    fi

    if ssh -o ConnectTimeout=10 "${ansible_user}@${ansible_host}" \
        "sudo tailscale set --advertise-routes=${routes}"; then
        after=$(get_routes)
        echo "  After:  $(tr '\n' ' ' <<< "$after" | xargs)"
        if grep -q "$routes" <<< "$after"; then
            echo "  ✓ Confirmed advertising $routes"
        else
            echo "  ✗ Set command succeeded but $routes still isn't showing — check manually" >&2
        fi
    else
        echo "  ✗ Failed to reach $alias or apply the route — check connectivity manually" >&2
    fi
    echo ""
done < <(grep 'tailscale_advertise_routes=' "$PROD_INI")

if [[ "$hosts_found" -eq 0 ]]; then
    echo "No hosts with tailscale_advertise_routes= found in $PROD_INI — nothing to do."
fi
