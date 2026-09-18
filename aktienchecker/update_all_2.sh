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

# Ticker-Liste kommt aus der Tabelle ticker_symbols (alle Zeilen, nicht nur
# aktive - anders als beim stuendlichen Lauf in run_hourly.sh). Es wird
# yahoo_symbol verwendet, weil get_lastdates.py diesen Wert direkt an
# yf.download() weiterreicht und zugleich (wegen index_prices.Ticker
# varchar(10)) als - auf 10 Zeichen abgeschnittenen - Ticker in die
# Datenbank schreibt; das entspricht dem bisherigen Verhalten der
# fest kodierten Liste.
TICKERS_RAW="$(mysql -N -B -e "
    SELECT yahoo_symbol
    FROM ticker_symbols
    WHERE yahoo_symbol IS NOT NULL
    ORDER BY ticker_symbol
")"
mysql_query_status=$?

if [ $mysql_query_status -ne 0 ]; then
    echo "FEHLER: Ticker-Liste konnte nicht aus ticker_symbols gelesen werden (mysql Exit-Code ${mysql_query_status})."
    exit 1
fi

if [ -z "$TICKERS_RAW" ]; then
    echo "Keine Ticker in ticker_symbols gefunden."
    exit 1
fi

mapfile -t tickers <<< "$TICKERS_RAW"

# venv aktivieren (set -u kurz aus, weil manche activate-Skripte auf
# nicht gesetzte Variablen zugreifen und sonst abbrechen würden)
set +u
source "$VENV_DIR/bin/activate"
set -u

# --- Hauptschleife über alle Ticker ---

fail_count=0

for ticker in "${tickers[@]}"; do
    [ -z "$ticker" ] && continue
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
