#!/bin/bash

# Set the Ansible configuration file path
export ANSIBLE_CONFIG=$PWD/ansible.cfg

# Run your Ansible playbook or command
ansible-playbook main.yml
