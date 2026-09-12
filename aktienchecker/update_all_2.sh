#!/bin/bash
#
# Aktualisiert die Kursdaten für eine Liste von Tickern über get_lastdates.py.
# Für den täglichen Lauf per Cron gedacht.

set -uo pipefail

# --- Robustheit: PATH, Arbeitsverzeichnis, Logging, Lock ---

export PATH=/usr/local/bin:/usr/bin:/bin

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="$SCRIPT_DIR/update_all.log"
exec >> "$LOG_FILE" 2>&1

LOCK_FILE="$SCRIPT_DIR/.update_all.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Ein anderer Lauf ist noch aktiv, breche ab."
    exit 1
fi

echo "=== Start: $(date '+%Y-%m-%d %H:%M:%S') ==="

# --- Konfiguration ---

VENV_DIR="/home/carsten/my_python"
PYTHON="$VENV_DIR/bin/python"
PY_SCRIPT="$SCRIPT_DIR/get_lastdates.py"

tickers=(
    "^GDAXI"
    "^GSPC"
    "^NDX"
    "^990100-USD-STRD"
    "^VIX"
    "^N225"
    "^RUT"
    "^STOXX"
    "EEM"
    "AAXJ"
)

# venv aktivieren (set -u kurz aus, weil manche activate-Skripte auf
# nicht gesetzte Variablen zugreifen und sonst abbrechen würden)
set +u
source "$VENV_DIR/bin/activate"
set -u

# --- Hauptschleife über alle Ticker ---

fail_count=0

for ticker in "${tickers[@]}"; do
    echo "Verarbeite Ticker $ticker..."
    if "$PYTHON" "$PY_SCRIPT" --ticker "$ticker"; then
        echo "OK: $ticker"
    else
        echo "FEHLER bei Ticker $ticker (Exit-Code $?)" >&2
        fail_count=$((fail_count + 1))
    fi
done

echo "=== Ende: $(date '+%Y-%m-%d %H:%M:%S'), $fail_count Fehler von ${#tickers[@]} Tickern ==="

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
