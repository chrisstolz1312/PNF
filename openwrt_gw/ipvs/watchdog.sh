#!/bin/sh

INTERVAL=60

echo "[WATCHDOG] Starte IPVS"

/ipvs.sh --setup || exit 1

echo "[WATCHDOG] Überwachung gestartet"

while true; do
    sleep "$INTERVAL"

    echo "[WATCHDOG] Prüfe IPv4 und IPv6"

    if ! /ipvs.sh --check; then
        echo "[WATCHDOG] Fehler erkannt!"

        ipvsadm -C

        echo "[WATCHDOG] Starte IPVS-Konfiguration neu"

        /ipvs.sh --setup || exit 1
    fi
done
