# IaC — Ansible playbooks

Automates infrastructure for the home lab (Zyron, nova, core-01, and Proxmox worker VMs).

## First time setup

```bash
./run.sh prep
```

This will:
1. Install Ansible if not already installed
2. Generate `.vault_pass` (gitignored) with a strong random password — **save it in a password manager**
3. Generate `group_vars/all/vault.yml` (gitignored) with a random Garage RPC secret and k3s token, then open it in your editor — fill in `ansible_become_pass` (sudo password for your servers)
4. Copy `inventory/hosts.example.ini` → `prod.ini` (gitignored) and open it in your editor — fill in real IPs

Then run the playbooks:

```bash
./run.sh homelab
```

## Commands

```bash
./run.sh prep             # first-time setup (install Ansible, create config files)
./run.sh prep --reset     # regenerate vault.yml and .vault_pass with new secrets
./run.sh homelab          # full home lab setup
./run.sh garage            # set up the Garage S3 node
./run.sh apt              # refresh apt cache on all nodes (add --tags upgrade to upgrade)
./run.sh timezone         # set timezone on all nodes
./run.sh --help           # show all commands
```

Extra arguments are passed through to `ansible-playbook`:

```bash
./run.sh homelab --tags k3s
./run.sh homelab --limit zyron --check
```

### Run multiple playbooks in one go

You can chain command names — each one runs as its own `ansible-playbook`
invocation, in order, with any trailing options applied to all of them.
Nothing is combined via ansible tags:

```bash
./run.sh homelab apt --limit zyron
# equivalent to:
#   ansible-playbook playbooks/setup-homelab.yml -i prod.ini --limit zyron
#   ansible-playbook playbooks/apt.yml -i prod.ini --limit zyron
```

### Run a playbook separately

`apt` and `timezone` are kept out of `homelab`/`garage` so they can be run on
their own, on any subset of nodes, without pulling in everything else:

```bash
# Refresh the apt cache only, on one node (safe, no package changes)
./run.sh apt --limit zyron

# Also upgrade packages (+ autoclean, autoremove)
./run.sh apt --limit zyron --tags upgrade

# Set timezone/locale on all nodes (does NOT reboot by default)
./run.sh timezone

# Same, but also reboot the node(s) afterwards to apply the change
./run.sh timezone --limit zyron --tags reboot
```

The upgrade task in `playbooks/apt.yml` and the reboot task in
`playbooks/timezone.yml` are both tagged `[<tag>, never]`, so they're always
skipped unless that tag is passed explicitly (`--tags upgrade` /
`--tags reboot`) — this keeps a routine run from unexpectedly upgrading
packages or rebooting a node.

## Fixing a dropped Tailscale route

k3s's CNI (flannel) interface churn on install/uninstall causes tailscaled to
clear a node's `AdvertiseRoutes` as a side effect (see
`roles/tailscale-routes-guard/`). `k3s-server`/`revert-k3s.yml` re-apply it
automatically at several checkpoints, but if you ever need to fix it by hand:

```bash
./fix-tailscale-routes.sh              # re-apply for every host with tailscale_advertise_routes set
./fix-tailscale-routes.sh --dry-run    # just show current state, change nothing
```

## Ansible Vault

Sensitive variables are stored encrypted in `group_vars/all/vault.yml`:

| Variable | Description |
|---|---|
| `vault_k3s_token` | Shared secret between k3s server and agents (auto-generated) |
| `vault_garage_rpc_secret` | Garage S3 internal RPC secret (auto-generated) |
| `ansible_become_pass` | Sudo password used by Ansible on managed nodes |

### Edit vault.yml

```bash
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Change ansible_become_pass

If your sudo password changes on the managed nodes:

```bash
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
# Update the ansible_become_pass line, save and close
```

### Change the vault password itself

```bash
ansible-vault rekey group_vars/all/vault.yml \
  --vault-password-file .vault_pass \
  --new-vault-password-file /dev/stdin
# Enter new password, update .vault_pass and Bitwarden
echo "new-password" > .vault_pass
chmod 600 .vault_pass
```

### View vault contents

```bash
ansible-vault view group_vars/all/vault.yml --vault-password-file .vault_pass
```

## Playbook structure

```
playbooks/
  setup-homelab.yml       full home lab setup (base config, k3s, add-ons)
  setup-garage.yml        Garage S3 node (base config, Garage S3, k3s agent)
  apt.yml                 apt cache refresh on all nodes; upgrade needs --tags upgrade (run.sh apt)
  timezone.yml            timezone + locale, run separately (run.sh timezone)
  revert-k3s.yml          cleanly remove k3s server/agent from a node (run.sh uninstall-k3s)
  k3s-server-debug.yml    same steps as k3s-server role, one per line — comment any out to
                          skip it when troubleshooting a server install manually
  k3s-uninstall-debug.yml same steps as revert-k3s.yml, one per line — comment any out to
                          skip it when troubleshooting an uninstall manually
```

## Role structure

```
roles/
  auto_update/           scheduled unattended-upgrades (systemd timers, runs unattended)
  security_updates/      immediate apt update + unattended-upgrade run + fail2ban
  base_packages/         common packages on all nodes
  passwordless_sudo/     configure passwordless sudo for the ansible user
  silent_motd/           quiet login message
  k3s-server/            install k3s server (Zyron, nova, core-01), steps split under tasks/steps/
  k3s-uninstall/         uninstall steps shared by revert-k3s.yml and k3s-uninstall-debug.yml
  k3s-agent/             join k3s cluster (worker-01/02 Proxmox VMs — agent-only, no control plane)
  tailscale-routes-guard/ checks + re-applies a node's Tailscale route advertisement; k3s's CNI
                          interface churn on install/uninstall clears it as a side effect (see
                          roles/k3s-server/tasks/main.yml for the confirmed root cause). Also
                          deploys/removes /usr/local/bin/fix-tailscale-routes.sh, chained onto
                          the k3s uninstall command itself so it self-heals immediately even if
                          the uninstall script is ever run outside of Ansible.
  nvidia-runtime/        containerd NVIDIA runtime (Zyron)
  garage-s3/             self-hosted S3 storage (nova)
  kueue/                 job queue with GPU priority tiers
  headlamp/              Kubernetes dashboard (NodePort 30800)
```

## Create a new role

```bash
ansible-galaxy init roles/my-role
```
