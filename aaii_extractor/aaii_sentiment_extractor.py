#!/usr/bin/env python3
"""
Liest die AAII "sentiment.xls" (Investor Sentiment Survey) ein und schreibt
die Bullish/Neutral/Bearish/Bull-Bear-Werte der letzten N Wochen per Upsert
in die MySQL-Tabelle market_sentiment.

Voraussetzungen (im venv installieren):
    pip install pandas xlrd pymysql

Erwartetes Tabellenschema (Beispiel aus der Aufgabenstellung):
    date        source  symbol      value
    2026-09-09  AAII    BEARISH     39.30000
    2026-09-09  AAII    BULL_BEAR   -1.300000
    2026-09-09  AAII    BULLISH     38.000000
    2026-09-09  AAII    NEUTRAL     22.700000

WICHTIG: Damit "ON DUPLICATE KEY UPDATE" wie ein echtes Upsert funktioniert,
braucht die Tabelle einen UNIQUE-/PRIMARY-KEY auf (date, source, symbol).
Beispiel-DDL, falls die Tabelle das noch nicht hat:

    CREATE TABLE IF NOT EXISTS market_sentiment (
        date    DATE            NOT NULL,
        source  VARCHAR(32)     NOT NULL,
        symbol  VARCHAR(32)     NOT NULL,
        value   DECIMAL(10,5)   NOT NULL,
        PRIMARY KEY (date, source, symbol)
    );

Nutzung:
    python3 aaii_sentiment_extractor.py sentiment.xls --weeks 5
    python3 aaii_sentiment_extractor.py sentiment.xls --weeks 5 --dry-run
    python3 aaii_sentiment_extractor.py sentiment.xls --mysql-defaults-file ~/.my.cnf

Verbindungsdaten werden NICHT im Skript hinterlegt, sondern aus der
my.cnf-Datei gelesen (Standard: ~/.my.cnf, Gruppe [client]).
"""

import argparse
import logging
import sys
from pathlib import Path

import pandas as pd

SHEET_NAME = "SENTIMENT"
HEADER_ROW = 3  # 0-basiert: Zeile 4 in Excel enthält "Date", "Bullish", ...
SOURCE = "AAII"
TABLE = "market_sentiment"

log = logging.getLogger("aaii_sentiment")


def setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )


def load_sentiment(xls_path: Path) -> pd.DataFrame:
    """Liest das SENTIMENT-Blatt und liefert nur echte, vollständige Wochen zurück."""
    try:
        df = pd.read_excel(xls_path, sheet_name=SHEET_NAME, header=HEADER_ROW, engine="xlrd")
    except Exception as exc:
        raise RuntimeError(
            f"Konnte '{xls_path}' nicht als Excel-Datei lesen ({exc}). "
            "Möglicherweise wurde beim Download eine Fehlerseite statt der "
            "echten sentiment.xls heruntergeladen."
        ) from exc

    df = df[["Date", "Bullish", "Neutral", "Bearish"]].copy()

    # Am Tabellenende stehen Zusammenfassungszeilen wie "Count '23" statt
    # echter Datumswerte in der Date-Spalte -> per to_datetime aussortieren.
    df["Date"] = pd.to_datetime(df["Date"], errors="coerce")
    df = df.dropna(subset=["Date", "Bullish", "Neutral", "Bearish"])
    df = df.sort_values("Date").reset_index(drop=True)

    if df.empty:
        raise RuntimeError("Keine gültigen Wochendaten in der Datei gefunden.")
    return df


def to_rows(df: pd.DataFrame, weeks: int) -> list[tuple]:
    """Wandelt die letzten `weeks` Wochen in (date, source, symbol, value)-Tupel um."""
    last_n = df.tail(weeks)
    rows: list[tuple] = []
    for _, r in last_n.iterrows():
        d = r["Date"].date()
        bullish = round(r["Bullish"] * 100, 5)
        neutral = round(r["Neutral"] * 100, 5)
        bearish = round(r["Bearish"] * 100, 5)
        bull_bear = round(bullish - bearish, 5)
        rows.append((d, SOURCE, "BULLISH", bullish))
        rows.append((d, SOURCE, "NEUTRAL", neutral))
        rows.append((d, SOURCE, "BEARISH", bearish))
        rows.append((d, SOURCE, "BULL_BEAR", bull_bear))
    return rows


def upsert_rows(rows: list[tuple], mysql_defaults_file: Path) -> int:
    import pymysql  # Import hier, damit --dry-run auch ohne pymysql funktioniert

    sql = (
        f"INSERT INTO {TABLE} (date, source, symbol, value) "
        "VALUES (%s, %s, %s, %s) "
        "ON DUPLICATE KEY UPDATE value = VALUES(value)"
    )

    conn = pymysql.connect(
        read_default_file=str(mysql_defaults_file.expanduser()),
        read_default_group="client",
        autocommit=False,
    )
    try:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
        return cur.rowcount
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def main() -> int:
    setup_logging()

    parser = argparse.ArgumentParser(description="AAII Sentiment Survey (.xls) -> MySQL market_sentiment")
    parser.add_argument("xls_path", type=Path, help="Pfad zur sentiment.xls")
    parser.add_argument("--weeks", type=int, default=5, help="Anzahl der letzten Wochen (Standard: 5)")
    parser.add_argument(
        "--mysql-defaults-file",
        type=Path,
        default=Path("~/.my.cnf"),
        help="my.cnf-Datei mit den DB-Zugangsdaten (Standard: ~/.my.cnf)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Nur einlesen und anzeigen, nichts in die Datenbank schreiben",
    )
    args = parser.parse_args()

    if not args.xls_path.exists():
        log.error("Datei nicht gefunden: %s", args.xls_path)
        return 1

    try:
        df = load_sentiment(args.xls_path)
        rows = to_rows(df, args.weeks)
    except Exception as exc:
        log.error("Fehler beim Einlesen/Aufbereiten: %s", exc)
        return 1

    log.info("Letzte %d Wochen aus %s eingelesen (%d Zeilen für DB).", args.weeks, args.xls_path, len(rows))
    for d, source, symbol, value in rows:
        log.info("  %s  %s  %-10s %10.5f", d, source, symbol, value)

    if args.dry_run:
        log.info("Dry-Run: keine Datenbankschreibung durchgeführt.")
        return 0

    try:
        affected = upsert_rows(rows, args.mysql_defaults_file)
    except ModuleNotFoundError:
        log.error("pymysql ist nicht installiert. Im venv installieren mit: pip install pymysql")
        return 1
    except Exception as exc:
        log.error("Fehler beim Schreiben in die Datenbank: %s", exc)
        return 1

    log.info("Upsert abgeschlossen, %d Zeilen betroffen (Insert zählt 1, Update zählt 2 je MySQL-Semantik).", affected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
