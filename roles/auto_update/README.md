auto_update
=========

This role will ensure that unattended updates is configured for Ubuntu.

Requirements
------------

No pre-requisites is required.

Role Variables
--------------

One should export the time for when the auto_update task should run.

Dependencies
------------

No dependencies.

Example Playbook
----------------

How to use the role:

    - hosts: servers
      roles:
         - { role: auto_update }

License
-------

BSD

Author Information
------------------

zolodev
