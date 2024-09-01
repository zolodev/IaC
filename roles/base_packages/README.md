base_packages
=========

This role will ensure that a few basic applications and packages are installed on the Ubuntu machine.

Requirements
------------

No pre-requisites is required.

Role Variables
--------------

One should probably move the default/main.yml list to the variables file instead.

Dependencies
------------

No dependencies.

Example Playbook
----------------

How to use the role:

    - hosts: servers
      roles:
         - { role: base_packages }

License
-------

BSD

Author Information
------------------

zolodev
