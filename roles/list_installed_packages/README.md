base_packages
=========

This role will get a list of all installed packages and versions.
Similar like an SBOM "Software Bill of Materials".

Requirements
------------

No pre-requisites is required.

Role Variables
--------------

One should probably move the the desired filename to the variables.

Dependencies
------------

No dependencies.

Example Playbook
----------------

How to use the role:

    - hosts: servers
      roles:
         - { role: list_installed_packages }

License
-------

BSD

Author Information
------------------

zolodev
