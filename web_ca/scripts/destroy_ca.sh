#!/bin/bash

set -e


echo "
==============================
DESTROY CA REQUEST
==============================
"


if [ ! -d /ca/pki ]
then
    echo "No CA exists"
    exit 0
fi


echo "Removing CA data"


rm -rf \
    /ca/pki \
    /ca/clients \
    /ca/*.key \
    /ca/*.pem \
    /ca/vars \
    /ca/easyrsa


echo "CA DESTROYED"

exit 0
