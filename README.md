# IoC - Ansible playbooks
This repo is to manage and automate my servers using Ansible.

´main.yml´ is the main playbook.
Run it with following command:
```sh
ansible-playbook main.yml -i inv.ini
```

Or run individual `playbooks`
```sh
ansible-playbook ./playbooks/apt.yml -i inv.ini
```