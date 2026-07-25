# IaC — Ansible playbooks

Automates infrastructure for the home lab (Jetson + Zimaboards + zh) and the RISE cluster.

## Prerequisites

```bash
pip install ansible
```

## First run

On the first run `run.sh` will automatically:
- Generate a random k3s token and Garage RPC secret
- Write `group_vars/vault.yml` (gitignored)
- Offer to encrypt it with ansible-vault and save `.vault_pass` (gitignored)

The only thing you need to do manually is create `prod.ini` with your real hosts:

```bash
cp inventory/hosts.example.ini prod.ini
# Edit prod.ini — fill in real IPs and hostnames
./run.sh homelab
```

On all subsequent runs `run.sh` picks up `.vault_pass` automatically — no extra flags needed.

## Running playbooks

```bash
./run.sh              # setup-homelab (default)
./run.sh homelab      # k3s + NVIDIA + sealed-secrets + kueue
./run.sh zh           # k3s agent + Garage S3 on zh
./run.sh base         # security updates on all nodes
./run.sh prep         # prepare the Ansible control host
```

With vault password prompt:
```bash
./run.sh homelab --ask-vault-pass
```

Or store the password locally (gitignored):
```bash
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
./run.sh homelab   # reads .vault_pass automatically
```

## Ansible Vault

Sensitive variables (k3s token, Garage RPC secret) are stored encrypted in `group_vars/vault.yml`.

```bash
# Encrypt
ansible-vault encrypt group_vars/vault.yml

# Edit
ansible-vault edit group_vars/vault.yml

# Change password
ansible-vault rekey group_vars/vault.yml

# View contents
ansible-vault view group_vars/vault.yml
```

Generate strong values:
```bash
openssl rand -hex 32   # k3s token
openssl rand -hex 32   # Garage RPC secret (must be 64 hex chars)
```

## Role structure

```
roles/
  auto_update/       security updates (unattended-upgrades)
  base_packages/     common packages on all nodes
  silent_motd/       quiet login message
  timezone/          timezone (Europe/Stockholm)
  k3s-server/        install k3s server+agent (Jetson)
  k3s-agent/         join k3s cluster (Zimaboards, zh)
  nvidia-runtime/    containerd NVIDIA runtime (Jetson)
  garage-s3/         self-hosted S3 storage (zh)
  sealed-secrets/    encrypted k8s secrets (GitOps-safe)
  kueue/             job queue with GPU priority tiers
```

## Create a new role

```bash
ansible-galaxy init roles/my-role
```
