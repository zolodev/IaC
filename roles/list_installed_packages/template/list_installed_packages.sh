#!/bin/bash
dpkg-query -W -f='${binary:Package}\n' | while read pkg; do
  echo "Package: $pkg"
  grep "install $pkg" /var/log/dpkg.log | awk '{print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'
done