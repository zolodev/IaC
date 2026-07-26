# IaC — Ansible playbooks

Automates infrastructure for the home lab (Jetson + Zimaboards + zh).

## First time setup

```bash
./run.sh prep
```

This will:
1. Install Ansible if not already installed
2. Generate `.vault_pass` (gitignored) with a strong random password — **save it in Bitwarden**
3. Generate `group_vars/vault.yml` (gitignored) with a random Garage RPC secret, then open it in your editor — fill in `vault_k3s_token` and `vault_become_pass` (sudo password for your servers)
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
./run.sh zh               # set up zh node only
./run.sh base             # apt security updates on all nodes
./run.sh --help           # show all commands
```

Extra arguments are passed through to `ansible-playbook`:

```bash
./run.sh homelab --tags k3s
./run.sh homelab --limit jetson --check
```

## Ansible Vault

Sensitive variables are stored encrypted in `group_vars/vault.yml`:

| Variable | Description |
|---|---|
| `vault_k3s_token` | Shared secret between k3s server and agents |
| `vault_garage_rpc_secret` | Garage S3 internal RPC secret (auto-generated) |
| `vault_become_pass` | Sudo password used by Ansible on managed nodes |

### Edit vault.yml

```bash
ansible-vault edit group_vars/vault.yml --vault-password-file .vault_pass
```

### Change vault_become_pass

If your sudo password changes on the managed nodes:

```bash
ansible-vault edit group_vars/vault.yml --vault-password-file .vault_pass
# Update the vault_become_pass line, save and close
```

### Change the vault password itself

```bash
ansible-vault rekey group_vars/vault.yml \
  --vault-password-file .vault_pass \
  --new-vault-password-file /dev/stdin
# Enter new password, update .vault_pass and Bitwarden
echo "new-password" > .vault_pass
chmod 600 .vault_pass
```

### View vault contents

```bash
ansible-vault view group_vars/vault.yml --vault-password-file .vault_pass
```

## Role structure

```
roles/
  auto_update/       security updates (unattended-upgrades)
  base_packages/     common packages + passwordless sudo
  silent_motd/       quiet login message
  timezone/          timezone (Europe/Stockholm)
  k3s-server/        install k3s server (Jetson)
  k3s-agent/         join k3s cluster (Zimaboards, zh)
  nvidia-runtime/    containerd NVIDIA runtime (Jetson)
  garage-s3/         self-hosted S3 storage (zh)
  sealed-secrets/    encrypted k8s secrets
  kueue/             job queue with GPU priority tiers
  headlamp/          Kubernetes dashboard (NodePort 30800)
```

## Create a new role

```bash
ansible-galaxy init roles/my-role
```
