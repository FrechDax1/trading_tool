#!/usr/bin/env bash
#
# dump_schema.sh — Schema-Dump der Hostinger-MySQL/MariaDB-Datenbank
#
# Zieht NUR die Struktur (keine Daten): Tabellen, Views, Trigger, Stored
# Procedures/Functions und Events. Gedacht, um regelmäßig (manuell oder per
# Cron) ausgeführt und der Output in Git committed zu werden, damit
# Schema-Änderungen versioniert und im Notfall wiederherstellbar sind.
#
# Verbindungsdaten (Host/User/Passwort) stehen bewusst NICHT in diesem
# Script und auch nicht in einer .env, sondern in deiner MySQL-Optionsdatei
# (Standard: ~/.my.cnf). mysql/mysqldump lesen diese Datei automatisch ein,
# es muss hier also nichts weiter angegeben werden.
#
# Falls deine Optionsdatei einen abweichenden Namen/Pfad hat (z.B. wirklich
# "~/.mycnf" ohne Punkt, statt des MySQL-Standards "~/.my.cnf"), das per
# MYCNF_FILE bekannt machen:
#   MYCNF_FILE=~/.mycnf ./dump_schema.sh meine_datenbank
#
# Voraussetzungen:
#   - mysql-client lokal installiert (liefert "mysqldump" und "mysql")
#   - Optionsdatei mit den Zugangsdaten existiert und ist nur für dich
#     lesbar (chmod 600 ~/.my.cnf)
#
# Nutzung:
#   ./dump_schema.sh meine_datenbank
#   (oder DB_NAME in einer .env neben diesem Script setzen, siehe .env.example
#   — die .env enthält dann KEINE Zugangsdaten mehr, nur noch den DB-Namen)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env-Datei laden, falls vorhanden (nur noch für DB_NAME gedacht)
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
  set +a
fi

DB_NAME="${1:-${DB_NAME:-}}"
: "${DB_NAME:?DB_NAME fehlt (als Argument uebergeben oder in .env setzen)}"

# Nur gesetzt, falls die Optionsdatei nicht am Standardpfad ~/.my.cnf liegt.
MYCNF_FILE="${MYCNF_FILE:-}"

CONN=()
if [[ -n "${MYCNF_FILE}" ]]; then
  # Muss als allererste Option uebergeben werden, das verlangt mysqldump/mysql so.
  CONN+=(--defaults-extra-file="${MYCNF_FILE}")
fi

OUT_DIR="${SCRIPT_DIR}/schema"
mkdir -p "${OUT_DIR}"

# Gemeinsame Optionen, die den Diff über mehrere Läufe hinweg sauber halten
COMMON_OPTS=(
  --no-data                 # keine Daten, nur Struktur
  --skip-dump-date          # kein Zeitstempel im Header -> stabiler Git-Diff
)

# --column-statistics gibt es nur beim MySQL-8-Client (nicht bei MariaDB oder
# älteren mysqldump-Versionen). Nur setzen, wenn die installierte Version es
# tatsächlich kennt, sonst bricht mysqldump mit "unknown variable" ab.
if mysqldump --help 2>/dev/null | grep -q -- '--column-statistics'; then
  COMMON_OPTS+=(--column-statistics=0)
fi

echo "==> Dumpe Schema von ${DB_NAME} (Zugangsdaten aus MySQL-Optionsdatei) ..."

# 1) Tabellen, Views, Trigger
mysqldump "${CONN[@]}" "${COMMON_OPTS[@]}" \
  --triggers \
  "${DB_NAME}" > "${OUT_DIR}/schema.sql"

# 2) Stored Procedures & Functions — eigene Datei, eigener Diff-Verlauf
mysqldump "${CONN[@]}" "${COMMON_OPTS[@]}" \
  --no-create-info \
  --skip-triggers \
  --routines \
  "${DB_NAME}" > "${OUT_DIR}/routines.sql"

# 3) Events (falls genutzt) — meist leer, aber der Vollständigkeit halber
mysqldump "${CONN[@]}" "${COMMON_OPTS[@]}" \
  --no-create-info \
  --skip-triggers \
  --events \
  "${DB_NAME}" > "${OUT_DIR}/events.sql"

echo "==> Fertig. Dump liegt in: ${OUT_DIR}"
echo "    - schema.sql     (Tabellen, Views, Trigger)"
echo "    - routines.sql   (Stored Procedures & Functions)"
echo "    - events.sql     (Events, falls vorhanden)"
echo ""
echo "Tipp: 'git add schema && git commit -m \"Schema-Stand $(date +%F)\"' zum Versionieren."
