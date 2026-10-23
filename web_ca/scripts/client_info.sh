#!/bin/bash

set -e


CLIENT=$1


CERT="/ca/pki/issued/$CLIENT.crt"



if [ -z "$CLIENT" ]
then

echo "missing client"
exit 1

fi



if [ ! -f "$CERT" ]
then

echo "
==============================
CLIENT INFO
==============================

Client:
$CLIENT

Status:
NOT FOUND
"

exit 1

fi



END=$(openssl x509 \
-in "$CERT" \
-noout \
-enddate \
| cut -d= -f2)



if openssl x509 \
-checkend 0 \
-noout \
-in "$CERT" >/dev/null
then

STATUS="VALID"

else

STATUS="EXPIRED"

fi



echo "
==============================
CLIENT INFO
==============================

Client:
$CLIENT

Status:
$STATUS

Expires:
$END
"
