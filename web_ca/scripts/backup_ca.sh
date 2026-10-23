#!/bin/bash

set -e


if [ ! -f /ca/pki/private/ca.key ]
then

echo "CA does not exist"
exit 1

fi


tar czf - \
-C / \
ca
