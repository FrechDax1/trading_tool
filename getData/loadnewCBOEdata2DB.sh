#!/bin/bash
#
# Lädt die tägliche CBOE Equity Put/Call Ratio der letzten 7 Tage und
# schreibt neue Werte in die Tabelle market_sentiment.
# Für den täglichen Lauf per Cron gedacht. DB-Zugangsdaten kommen aus
# ~/.my.cnf (Abschnitt [client]) des Users, unter dem der Cronjob läuft.

set -uo pipefail

# --- Robustheit: PATH, Arbeitsverzeichnis, Logging, Lock ---

export PATH=/usr/local/bin:/usr/bin:/bin

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="$SCRIPT_DIR/cboe_import.log"
exec >> "$LOG_FILE" 2>&1

LOCK_FILE="$SCRIPT_DIR/.cboe_import.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Ein anderer Lauf ist noch aktiv, breche ab."
    exit 1
fi

echo "=== Start: $(date '+%Y-%m-%d %H:%M:%S') ==="

# --- Konfiguration ---

start_date=$(date -d "7 days ago" +%Y-%m-%d)
end_date=$(date +%Y-%m-%d)
output_file="$SCRIPT_DIR/ergebnisse_latest.sql"
source_name="CBOE"   # nicht "source" nennen, das ist ein Bash-Builtin
symbol="EQUITY_PC"
base_url="https://www.cboe.com/markets/us/options/market-statistics/daily"

rm -f "$output_file"

current="$start_date"

while [ "$(date -d "$current" +%Y%m%d)" -le "$(date -d "$end_date" +%Y%m%d)" ]; do
    # Wochentag ermitteln (1 = Montag ... 7 = Sonntag)
    day_of_week=$(date -d "$current" +%u)

    # Nur Werktage verarbeiten (Montag bis Freitag)
    if [ "$day_of_week" -lt 6 ]; then
        echo "Verarbeite $current..."

        val=$(wget -q --timeout=20 --tries=2 -O - "${base_url}?dt=${current}" \
            | sed -En 's/.*EQUITY PUT\/CALL RATIO\\",\\"value\\":\\"([0-9.]+)\\"\}.*/\1/p') || val=""

        if [ -n "$val" ]; then
            echo "INSERT INTO market_sentiment (date, source, symbol, value) VALUES ('${current}', '${source_name}', '${symbol}', ${val}) ON DUPLICATE KEY UPDATE value = VALUES(value);" >> "$output_file"
        else
            echo "Kein Wert für $current gefunden."
        fi
    fi

    current=$(date -d "$current + 1 day" +%Y-%m-%d)
done

# --- Ergebnisse importieren ---

if [ -s "$output_file" ]; then
    echo "Schreibe Ergebnisse aus '$output_file' in die Datenbank..."
    if mysql < "$output_file"; then
        echo "Import erfolgreich."
    else
        echo "FEHLER: mysql-Import fehlgeschlagen." >&2
        exit 1
    fi
else
    echo "Keine neuen Werte gefunden, kein Import notwendig."
fi

echo "=== Ende: $(date '+%Y-%m-%d %H:%M:%S') ==="
