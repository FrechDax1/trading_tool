#!/usr/bin/env bash
#
# aaii_sentiment_cron.sh
#
# Lädt die aktuelle AAII "sentiment.xls" herunter, prüft sie, und schreibt
# die letzten Wochen per Upsert in die MySQL-Tabelle market_sentiment.
# Für den Betrieb per cron ausgelegt:
#   - nur absolute Pfade (cron kennt kein $HOME/keine Shell-Profile)
#   - kein "source .../activate" (siehe Hinweis unten), stattdessen wird
#     der venv-Python direkt aufgerufen
#   - flock verhindert überlappende Läufe, falls ein Lauf mal länger dauert
#   - komplette Textausgabe (wget + Python) landet in einer einzigen LOG_FILE
#   - eindeutige Exit-Codes: 0 = ok, 1 = Fehler
#
# Warum kein "source venv/bin/activate" im Cron-Skript?
#   activate-Skripte referenzieren oft $PS1 & Co. Mit "set -u" (s.u.) bricht
#   das unter cron/nicht-interaktiven Shells gern mit "unbound variable" ab.
#   Robuster: einfach direkt die venv-eigene python3-Binary aufrufen, das
#   entspricht funktional der Aktivierung.

set -euo pipefail

# --- Anpassbare Konfiguration -----------------------------------------------
BASE_DIR="/home/carsten/git/trading_tool/aaii_extractor"
VENV_PYTHON="/home/carsten/my_python/bin/python3"
PY_SCRIPT="${BASE_DIR}/aaii_sentiment_extractor.py"
XLS_FILE="${BASE_DIR}/sentiment.xls"
LOG_FILE="${BASE_DIR}/aaii_sentiment.log"
LOCK_FILE="${BASE_DIR}/aaii_sentiment.lock"
MYSQL_DEFAULTS_FILE="${HOME}/.my.cnf"
WEEKS=5
SENTIMENT_URL="https://www.aaii.com/files/surveys/sentiment.xls"
# -----------------------------------------------------------------------------

mkdir -p "$BASE_DIR"

# Nur einen Lauf gleichzeitig zulassen (wichtig bei cron, falls ein Lauf
# mal hängt/langsam ist und der nächste schon anspringt).
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "$(date '+%F %T') WARN  Vorheriger Lauf läuft noch, breche ab." >>"$LOG_FILE"
    exit 0
fi

# Ab hier: gesamte Ausgabe (stdout+stderr) an die Logdatei anhängen.
exec >>"$LOG_FILE" 2>&1

echo "===== $(date '+%F %T') Start aaii_sentiment_cron.sh ====="

TMP_FILE="$(mktemp "${BASE_DIR}/sentiment.XXXXXX")"

if ! wget --quiet \
     --tries=3 \
     --timeout=30 \
     --header="User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" \
     --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
     --header="Accept-Language: en-US,en;q=0.9" \
     --header="Accept-Encoding: gzip, deflate, br" \
     --header="Referer: https://www.aaii.com/sentimentsurvey" \
     --header="Sec-Fetch-Dest: document" \
     --header="Sec-Fetch-Mode: navigate" \
     --header="Sec-Fetch-Site: same-origin" \
     --header="Upgrade-Insecure-Requests: 1" \
     -O "$TMP_FILE" \
     "$SENTIMENT_URL"; then
    echo "$(date '+%F %T') ERROR Download fehlgeschlagen (wget-Fehler)."
    rm -f "$TMP_FILE"
    exit 1
fi

if [ ! -s "$TMP_FILE" ]; then
    echo "$(date '+%F %T') ERROR Heruntergeladene Datei ist leer."
    rm -f "$TMP_FILE"
    exit 1
fi

# Grobe Plausibilitätsprüfung: eine echte sentiment.xls ist eine binäre
# "Composite Document File" (OLE2). Falls stattdessen z.B. eine
# Cloudflare-Fehlerseite (HTML) kam, NICHT die letzte gute Datei überschreiben.
FILE_TYPE="$(file -b "$TMP_FILE")"
case "$FILE_TYPE" in
    *"Composite Document"*|*"CDF V2"*)
        mv "$TMP_FILE" "$XLS_FILE"
        echo "$(date '+%F %T') INFO  Download ok: $XLS_FILE ($(stat -c%s "$XLS_FILE") Bytes)"
        ;;
    *)
        echo "$(date '+%F %T') ERROR Heruntergeladene Datei sieht nicht wie eine gültige Excel-Datei aus (file: $FILE_TYPE). Vorherige $XLS_FILE bleibt unverändert."
        rm -f "$TMP_FILE"
        exit 1
        ;;
esac

if ! "$VENV_PYTHON" "$PY_SCRIPT" "$XLS_FILE" --weeks "$WEEKS" --mysql-defaults-file "$MYSQL_DEFAULTS_FILE"; then
    echo "$(date '+%F %T') ERROR Python-/DB-Schritt fehlgeschlagen."
    exit 1
fi

echo "===== $(date '+%F %T') Ende aaii_sentiment_cron.sh (OK) ====="
