#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# PNF Backup
#
# Sichert alle sichtbaren Dateien und Verzeichnisse aus dem
# Home-Verzeichnis in ein komprimiertes TAR-Archiv.
#
# - Versteckte Dateien und Verzeichnisse werden ausgeschlossen.
# - backup.sh wird ebenfalls gesichert.
# - Dateirechte und Eigentümer bleiben erhalten.
# - Das Backup wird außerhalb des Home-Verzeichnisses abgelegt.
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKUP_DIR="/tmp/pnf-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/pnf-home-$TIMESTAMP.tar.gz"

echo "============================================"
echo " PNF BACKUP"
echo "============================================"
echo

# ------------------------------------------------------------
# Backup-Verzeichnis vorbereiten
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

echo "[INFO] Quelle: $ROOT"
echo "[INFO] Ziel:   $BACKUP_FILE"
echo

# ------------------------------------------------------------
# TAR-Archiv erstellen
#
# Der Punkt am Ende bedeutet: gesamtes ROOT-Verzeichnis.
# Versteckte Dateien und Verzeichnisse werden ausgeschlossen.
#
# WICHTIG:
# backup.sh wird NICHT ausgeschlossen und ist somit enthalten.
# ------------------------------------------------------------

echo "[INFO] Erstelle Backup ..."

tar \
    --create \
    --gzip \
    --file="$BACKUP_FILE" \
    --directory="$ROOT" \
    --exclude='*/.*' \
    --exclude='./.*' \
    .

# ------------------------------------------------------------
# Backup prüfen
# ------------------------------------------------------------

echo "[INFO] Prüfe Backup ..."

tar -tzf "$BACKUP_FILE" >/dev/null

if tar -tzf "$BACKUP_FILE" | grep -Fxq './backup.sh'; then
    echo "[OK] backup.sh ist im Archiv enthalten."
else
    echo "[ERROR] backup.sh fehlt im Archiv!"
    exit 1
fi

# ------------------------------------------------------------
# Abschluss
# ------------------------------------------------------------

echo
echo "============================================"
echo " PNF BACKUP ERFOLGREICH"
echo "============================================"
echo

echo "[OK] Backup erstellt:"
echo "$BACKUP_FILE"

echo
echo "[INFO] Archivgröße:"
du -h "$BACKUP_FILE"
