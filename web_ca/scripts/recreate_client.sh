#!/bin/bash

set -e

export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki


CLIENT=$1


if [ -z "$CLIENT" ]
then
echo "missing client"
exit 1
fi


cd /ca


echo "
==============================
FORCE RESET CLIENT
==============================
"


echo "Removing exported client"


rm -rf \
"/ca/clients/$CLIENT"



echo "Removing certificate files"


rm -f \
"/ca/pki/issued/$CLIENT.crt" \
"/ca/pki/private/$CLIENT.key" \
"/ca/pki/reqs/$CLIENT.req" \
"/ca/pki/inline/$CLIENT.inline"



echo "Cleaning cert serial links"


SERIALS=$(grep "/CN=$CLIENT$" /ca/pki/index.txt \
| awk '{print $4}' || true)


for S in $SERIALS
do

rm -f \
"/ca/pki/certs_by_serial/$S.pem"


rm -rf \
"/ca/pki/revoked/certs_by_serial/$S.crt" \
"/ca/pki/revoked/private_by_serial/$S.key" \
"/ca/pki/revoked/reqs_by_serial/$S.req"

done




echo "Cleaning index"


grep -v \
"/CN=$CLIENT$" \
/ca/pki/index.txt \
> /tmp/index.txt


cat /tmp/index.txt \
> /ca/pki/index.txt





echo "Creating fresh client"


/scripts/client.sh "$CLIENT"



echo "
CLIENT FORCE CREATED
"
