auto_update
=========

This role will ensure that unattended updates is configured for Ubuntu.

Requirements
------------

No pre-requisites is required.

Role Variables
--------------

## Time
The configuration file have a randomize 60m by default.
This is to avoid that schedule tasks will run at the same time.

### Default daily time values
```yml
time:
  hour: "14"     # schedule time 02:00
  minutes: "30"
```


Dependencies
------------

No dependencies.

Example Playbook
----------------

How to use the role:

Shorthand:
```yml
    - hosts: servers
      roles:
         - auto_update
```
Full:
```yml
    - hosts: servers
      roles:
         - role: auto_update
           daily_time:
            hour: "14"     # schedule time 14:30
            minutes: "30"
```

License
-------

BSD

Author Information
------------------

zolodev
