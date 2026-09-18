#!/bin/bash
# Zentraler Wrapper fuer den stuendlichen Cron-Aufruf.
#
# Holt sich selbst die Liste der aktiven, vollstaendig konfigurierten Ticker
# aus ticker_symbols und ruft index_prices.py EINZELN pro Ticker auf
# (python3 index_prices.py <ticker_symbol>). Nur wenn dabei tatsaechlich
# neue Kurse geschrieben wurden (Exit-Code 0), wird anschliessend fuer
# genau diesen Ticker die Indikator-Stored-Procedure aufgerufen:
#   CALL sp_approx_indicators_today('<ticker_symbol>', CURDATE(), 150);
#
# MySQL-Zugangsdaten kommen wie beim mysql-Client selbst aus ~/.my.cnf -
# hier wird bewusst kein Host/User/Passwort angegeben.
#
# Cron-Beispiel (stuendlich, Mo-Fr):
#   0 * * * 1-5 /pfad/zu/run_hourly.sh >> /var/log/index_prices.log 2>&1
#
# Exit-Codes:
#   0  OK - mindestens ein Ticker geschrieben, keine Fehler
#   1  Fehler bei mindestens einem Ticker (Kursabruf, Schreiben, Indikatoren)
#   2  nichts geschrieben, aber auch kein Fehler (Boersen zu / keine neuen Werte)
#   4  Skript laeuft bereits (Lock nicht erhalten) - kein neuer Durchlauf gestartet

set -uo pipefail
# Bewusst KEIN "set -e": das Skript verarbeitet mehrere Ticker nacheinander
# und muss nach einem Fehler bei einem Ticker trotzdem mit den naechsten
# weitermachen; jeder Exit-Code wird explizit ausgewertet.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# --- Konfiguration ---
VENV_DIR="/home/carsten/my_python"
PYTHON="$VENV_DIR/bin/python"
PY_SCRIPT="$SCRIPT_DIR/index_prices.py"

INDICATOR_LOOKBACK_DAYS=150

if [ ! -x "$PYTHON" ]; then
    echo "[${SCRIPT_NAME}] FEHLER: Python-Interpreter nicht gefunden oder nicht ausfuehrbar: ${PYTHON} (venv unter ${VENV_DIR} vorhanden?)"
    exit 1
fi

if [ ! -f "$PY_SCRIPT" ]; then
    echo "[${SCRIPT_NAME}] FEHLER: Skript nicht gefunden: ${PY_SCRIPT}"
    exit 1
fi

# ---------------------------------------------------------------------------
# 0) Lock, damit nicht zwei Laeufe gleichzeitig aktiv sein koennen (z.B. wenn
#    ein Durchlauf laenger dauert als das Cron-Intervall). flock haelt den
#    Lock ueber den Datei-Deskriptor - der wird beim Skriptende IMMER
#    freigegeben, auch bei einem Absturz, ohne dass ein Stale-Lock-File
#    manuell aufgeraeumt werden muss (anders als bei einer reinen PID-Datei).
# ---------------------------------------------------------------------------
LOCK_FILE="${LOCK_FILE:-${SCRIPT_DIR}/.run_hourly.lock}"
LOCK_FD=200

if ! command -v flock >/dev/null 2>&1; then
    echo "[${SCRIPT_NAME}] FEHLER: 'flock' ist nicht installiert - kann Lock nicht absichern, breche ab."
    exit 1
fi

eval "exec ${LOCK_FD}>\"${LOCK_FILE}\""
if ! flock -n "$LOCK_FD"; then
    echo "[${SCRIPT_NAME}] Ein anderer Lauf ist bereits aktiv (Lock: ${LOCK_FILE}) - breche ab, kein neuer Durchlauf gestartet."
    exit 4
fi

# ---------------------------------------------------------------------------
# 1) Liste der aktiven, vollstaendig konfigurierten Ticker holen
#    (dieselbe Filterbedingung wie in index_prices.py's load_ticker_configs)
# ---------------------------------------------------------------------------
TICKERS_RAW="$(mysql -N -B -e "
    SELECT ticker_symbol
    FROM ticker_symbols
    WHERE active = 1
      AND yahoo_symbol IS NOT NULL
      AND market_open IS NOT NULL
      AND market_close IS NOT NULL
      AND market_timezone IS NOT NULL
    ORDER BY ticker_symbol
")"
mysql_query_status=$?

if [ $mysql_query_status -ne 0 ]; then
    echo "[${SCRIPT_NAME}] FEHLER: Ticker-Liste konnte nicht aus ticker_symbols gelesen werden (mysql Exit-Code ${mysql_query_status})."
    exit 1
fi

mapfile -t TICKERS <<< "$TICKERS_RAW"

# Falls TICKERS_RAW leer war, enthaelt TICKERS jetzt ein einzelnes leeres
# Element - das wird beim Filtern unten uebersprungen.
if [ -z "$TICKERS_RAW" ]; then
    echo "[${SCRIPT_NAME}] Keine aktiven/vollstaendig konfigurierten Ticker in ticker_symbols gefunden."
    exit 2
fi

# ---------------------------------------------------------------------------
# 2) Pro Ticker: Kurse abrufen, bei Erfolg Indikatoren aktualisieren
# ---------------------------------------------------------------------------
any_written=0
any_error=0

for ticker in "${TICKERS[@]}"; do
    [ -z "$ticker" ] && continue

    # Zulassen: Buchstaben, Ziffern, Unterstrich, Punkt, Caret (^) und
    # Bindestrich - deckt sowohl kurze interne Kennungen (DAX40) als auch
    # rohe Yahoo-Symbole als ticker_symbol ab (^GDAXI, ^990100-USD-STRD).
    # Bewusst NICHT erlaubt: Anfuehrungszeichen, Backslash, Semikolon,
    # Leerzeichen - das sind die Zeichen, die im rohen SQL-Statement
    # (CALL ...) unten tatsaechlich gefaehrlich waeren.
    if [[ ! "$ticker" =~ ^[A-Za-z0-9_.^-]+$ ]]; then
        echo "[${SCRIPT_NAME}] ${ticker}: unerwartetes Format, wird uebersprungen (moegliche SQL-Injection-Quelle)."
        any_error=1
        continue
    fi

    echo "[${SCRIPT_NAME}] ${ticker}: verarbeite ..."

    "$PYTHON" "$PY_SCRIPT" "${ticker}"
    ticker_exit=$?

    case $ticker_exit in
        0)
            echo "[${SCRIPT_NAME}] ${ticker}: OK - Kurse geschrieben."
            any_written=1

            echo "[${SCRIPT_NAME}] ${ticker}: aktualisiere Indikatoren (sp_approx_indicators_today) ..."
            mysql -e "CALL sp_approx_indicators_today('${ticker}', CURDATE(), ${INDICATOR_LOOKBACK_DAYS});"
            indicator_exit=$?
            if [ $indicator_exit -ne 0 ]; then
                echo "[${SCRIPT_NAME}] ${ticker}: FEHLER beim Aktualisieren der Indikatoren (Exit-Code ${indicator_exit})."
                any_error=1
            fi
            ;;
        1)
            echo "[${SCRIPT_NAME}] ${ticker}: FEHLER beim Kursabruf/-schreiben (Exit-Code 1)."
            any_error=1
            ;;
        2)
            echo "[${SCRIPT_NAME}] ${ticker}: keine neuen Kurse (Boerse zu / kein neuer Tageswert) - kein Fehler."
            ;;
        3)
            echo "[${SCRIPT_NAME}] ${ticker}: ungueltiger/nicht konfigurierter Ticker (Exit-Code 3)."
            any_error=1
            ;;
        *)
            echo "[${SCRIPT_NAME}] ${ticker}: unbekannter Exit-Code ${ticker_exit}."
            any_error=1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# 3) Gesamt-Exit-Code (gleiche Semantik wie zuvor: 0=OK, 1=Fehler,
#    2=nichts geschrieben aber auch kein Fehler)
# ---------------------------------------------------------------------------
if [ $any_error -eq 1 ]; then
    overall_status=1
elif [ $any_written -eq 0 ]; then
    overall_status=2
else
    overall_status=0
fi

echo "[${SCRIPT_NAME}] Gesamtergebnis: Exit-Code ${overall_status}"
exit $overall_status
