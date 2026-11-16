#!/bin/sh

INTERVAL=60
HEALTHCHECK_PID=""

start_healthchecker() {
    echo "[WATCHDOG] Starte Healthchecker"
    /healthcheck.sh &
    HEALTHCHECK_PID=$!
    echo "[WATCHDOG] Healthchecker PID=$HEALTHCHECK_PID"
}

stop_healthchecker() {
    if [ -n "$HEALTHCHECK_PID" ]; then
        kill "$HEALTHCHECK_PID" 2>/dev/null || :
        wait "$HEALTHCHECK_PID" 2>/dev/null || :
    fi
}

trap 'stop_healthchecker; exit 0' TERM INT
trap 'stop_healthchecker' EXIT

echo "[WATCHDOG] Starte IPVS"

/ipvs.sh --setup || exit 1

start_healthchecker

echo "[WATCHDOG] Überwachung gestartet"

while true; do
    sleep "$INTERVAL" &
    wait $!

    # Healthchecker bei unerwartetem Ende neu starten.
    if ! kill -0 "$HEALTHCHECK_PID" 2>/dev/null; then
        echo "[WATCHDOG] Healthchecker beendet – Neustart"
        wait "$HEALTHCHECK_PID" 2>/dev/null || :
        start_healthchecker
    fi

    echo "[WATCHDOG] Prüfe IPv4 und IPv6"

    if ! /ipvs.sh --check; then
        echo "[WATCHDOG] Fehler erkannt!"

        echo "[WATCHDOG] Starte IPVS-Konfiguration neu"

        /ipvs.sh --setup || exit 1

        # Der Healthchecker gleicht die tatsächlichen Gewichte
        # im nächsten Prüfzyklus automatisch wieder ab.
    fi
done
