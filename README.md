# IoC - Ansible playbooks
This repo is to manage and automate my servers using Ansible.

# Pre-requisite
In Windows `WSL` we need to export the variable `ANSIBLE_CONFIG`:
```sh
export ANSIBLE_CONFIG=/mnt/c/Users/Zolo/projects/IoC/ansible.cfg
```

´main.yml´ is the main playbook.
Run it with following command:
```sh
ansible-playbook main.yml -i inv.ini
```

Or run individual `playbooks`
```sh
ansible-playbook ./playbooks/apt.yml -i inv.ini
```