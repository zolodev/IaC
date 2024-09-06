#!/bin/bash

# Set the Ansible configuration file path
export ANSIBLE_CONFIG=$PWD/ansible.cfg

# Define the file to check
PROD_INI="$PWD/prod.ini"

# Check if the file exists
if [ -f "$PROD_INI" ]; then
    echo "$PROD_INI exists. Running ansible-playbook..."
    
    # Run Ansible production playbook
    ansible-playbook main.yml -i $PROD_INI
    
else
    echo "$PROD_INI does not exist. Running default command..."
    ansible-playbook main.yml
fi


