#!/usr/bin/env python3
"""
index_prices.py

Holt Open/High/Low/Close/Volume des aktuellen Handelstags von Yahoo Finance
(per yfinance, 5-Minuten-Kerzen) und schreibt das Ergebnis nach MySQL in die
Tabelle `index_prices` (PK: Ticker, Date).

Welche Ticker abgefragt werden und wann das ueberhaupt sinnvoll ist, steht
in der Tabelle `ticker_symbols` (Spalten yahoo_symbol, market_open,
market_close, market_timezone, active). Damit reicht EIN zentraler,
z.B. stuendlicher Cron-Aufruf ohne Parameter - das Skript entscheidet pro
Ticker selbst, ob die Boerse gerade offen ist, und ueberspringt alles
andere, ohne ueberhaupt bei Yahoo anzufragen.

Die MySQL-Zugangsdaten werden NICHT im Skript oder in einer eigenen
Config-Datei gehalten, sondern wie beim `mysql`-Kommandozeilenclient aus
einer Optionsdatei gelesen (Default: ~/.my.cnf, Gruppe [client]). Falls
dort kein `database` gesetzt ist, muss die Datenbank per --database
angegeben werden.

Aufruf:
    python3 index_prices.py                # alle aktiven/konfigurierten Ticker
    python3 index_prices.py DAX40          # nur einen bestimmten Ticker
    python3 index_prices.py DAX40 --force  # Handelszeiten-Pruefung ignorieren
                                            # (z.B. zum manuellen Testen)

Verhalten pro Ticker:
  - Handelszeiten-Check zuerst (aus ticker_symbols, in der jeweiligen
    Boersen-Zeitzone, Mo-Fr). Ausserhalb der Handelszeit wird Yahoo gar
    nicht erst angefragt.
  - Danach `history(period="1d", interval="5m")`. Ist die letzte Kerze
    nicht von "heute" (Boersenzeit) - typischerweise weil Yahoo noch den
    Schlusskurs von gestern liefert - wird NICHTS geschrieben.
  - Insert/Update pro (Ticker, Date) via INSERT ... ON DUPLICATE KEY
    UPDATE, damit wiederholte Aufrufe waehrend des Handelstags den
    Datensatz aktualisieren statt Duplikate zu erzeugen.

Exit-Codes (fuer Cron/Monitoring auswertbar):
    0  OK - mindestens ein Ticker wurde geschrieben, keine Fehler
    1  Fehler (DB-Verbindung, Yahoo-Abruf, Schreibfehler o.ae.)
       bei mindestens einem Ticker
    2  Kein einziger Ticker geschrieben, aber auch kein Fehler
       (alle Boersen zu und/oder kein neuer Tageswert) - bewusst
       uebersprungen
    3  Angegebener Ticker existiert nicht oder ist nicht vollstaendig
       konfiguriert (yahoo_symbol/market_open/market_close/
       market_timezone/active fehlen)
"""

import argparse
import datetime as dt
import logging
import sys
from zoneinfo import ZoneInfo

import pandas as pd
import pymysql
import pymysql.cursors
import yfinance as yf

# ---------------------------------------------------------------------------
# Exit codes
# ---------------------------------------------------------------------------
EXIT_OK = 0
EXIT_ERROR = 1
EXIT_NO_NEW_DATA = 2
EXIT_INVALID_TICKER = 3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
log = logging.getLogger("index_prices")


# ---------------------------------------------------------------------------
# DB-Verbindung ueber MySQL-Optionsdatei (Standard: ~/.my.cnf), genau wie
# beim `mysql`-Kommandozeilenclient - keine eigenen Zugangsdaten im Skript
# oder in einer separaten Config-Datei.
# ---------------------------------------------------------------------------
def get_connection(defaults_file: str, defaults_group: str, database: str | None) -> pymysql.connections.Connection:
    connect_kwargs = dict(
        read_default_file=defaults_file,
        read_default_group=defaults_group,
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )
    # PyMySQL uebernimmt einen hier explizit gesetzten Wert bevorzugt vor dem
    # aus der Optionsdatei; bei database=None wird ausschliesslich das
    # 'database=' aus der Optionsdatei (falls vorhanden) verwendet.
    if database:
        connect_kwargs["database"] = database

    conn = pymysql.connect(**connect_kwargs)

    with conn.cursor() as cur:
        cur.execute("SELECT DATABASE() AS db")
        row = cur.fetchone()

    if not row or not row["db"]:
        conn.close()
        raise RuntimeError(
            f"Keine Datenbank ausgewaehlt: weder --database angegeben noch 'database' in "
            f"{defaults_file} [{defaults_group}] gesetzt."
        )

    return conn


# ---------------------------------------------------------------------------
# Ticker-Konfiguration aus ticker_symbols laden
# ---------------------------------------------------------------------------
def _timedelta_to_time(value) -> dt.time:
    """
    pymysql liefert MySQL-TIME-Spalten als datetime.timedelta zurueck.
    Wandelt das in ein datetime.time um (Werte >= 24h oder negativ
    werden nicht erwartet, da es sich um Uhrzeiten innerhalb eines
    Handelstages handelt).
    """
    if isinstance(value, dt.timedelta):
        total_seconds = int(value.total_seconds())
        hours, remainder = divmod(total_seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        return dt.time(hour=hours, minute=minutes, second=seconds)
    if isinstance(value, dt.time):
        return value
    raise TypeError(f"Unerwarteter Typ fuer Uhrzeit-Spalte: {type(value)!r}")


def load_ticker_configs(conn, only_ticker: str | None = None) -> list[dict]:
    """
    Laedt alle Ticker aus ticker_symbols, die vollstaendig fuer den
    automatischen Kursabruf konfiguriert sind:
    active=1 UND yahoo_symbol/market_open/market_close/market_timezone
    alle gesetzt.

    Mit only_ticker wird auf genau diesen Ticker gefiltert (auch dann muss
    er vollstaendig konfiguriert sein, sonst kommt eine leere Liste zurueck).
    """
    sql = """
        SELECT ticker_symbol, ticker_symbol_long, yahoo_symbol,
               market_open, market_close, market_timezone
        FROM ticker_symbols
        WHERE active = 1
          AND yahoo_symbol IS NOT NULL
          AND market_open IS NOT NULL
          AND market_close IS NOT NULL
          AND market_timezone IS NOT NULL
    """
    params = ()
    if only_ticker is not None:
        sql += " AND ticker_symbol = %s"
        params = (only_ticker,)

    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    configs = []
    for row in rows:
        configs.append(
            {
                "ticker_symbol": row["ticker_symbol"],
                "ticker_symbol_long": row["ticker_symbol_long"],
                "yahoo_symbol": row["yahoo_symbol"],
                "market_open": _timedelta_to_time(row["market_open"]),
                "market_close": _timedelta_to_time(row["market_close"]),
                "market_timezone": row["market_timezone"],
            }
        )
    return configs


# ---------------------------------------------------------------------------
# Handelszeiten-Check
# ---------------------------------------------------------------------------
def is_market_hours_now(market_open: dt.time, market_close: dt.time, market_timezone: str) -> bool:
    """
    Prueft, ob JETZT (aktueller Moment) innerhalb der Handelszeiten liegt -
    ausgewertet in der Zeitzone der jeweiligen Boerse, nicht in Berlin-Zeit.
    Nimmt Handelstage Montag-Freitag an (Boersenfeiertage werden nicht
    beruecksichtigt - an einem Feiertag liefert Yahoo ohnehin keine neuen
    Intraday-Daten, das faengt die spaetere "ist der Kurs von heute"-Pruefung
    zusaetzlich ab).
    """
    tz = ZoneInfo(market_timezone)
    now = dt.datetime.now(tz)

    if now.weekday() >= 5:  # Samstag=5, Sonntag=6
        return False

    return market_open <= now.time() <= market_close


# ---------------------------------------------------------------------------
# Yahoo Finance
# ---------------------------------------------------------------------------
def fetch_today_ohlcv(yahoo_symbol: str):
    """
    Holt 5-Minuten-Kerzen des aktuellen Handelstags und aggregiert sie zu
    Open/High/Low/Close/Volume + Zeitstempel der letzten Kerze.

    Gibt None zurueck, wenn gar keine Daten verfuegbar sind.
    """
    ticker = yf.Ticker(yahoo_symbol)
    hist = ticker.history(period="1d", interval="5m")

    if hist.empty:
        return None

    open_price = float(hist["Open"].iloc[0])
    high_price = float(hist["High"].max())
    low_price = float(hist["Low"].min())
    close_price = float(hist["Close"].iloc[-1])
    volume = hist["Volume"].sum()
    volume = int(volume) if pd.notna(volume) else 0

    last_timestamp = hist.index[-1]  # tz-aware pandas.Timestamp (Boersen-Zeitzone)

    return {
        "open": open_price,
        "high": high_price,
        "low": low_price,
        "close": close_price,
        "volume": volume,
        "last_timestamp": last_timestamp,
    }


def is_from_today(last_timestamp: pd.Timestamp) -> bool:
    """
    Prueft, ob der Zeitstempel der letzten Kerze von "heute" ist -
    verglichen in der Zeitzone der jeweiligen Boerse (last_timestamp.tz).
    """
    now_in_exchange_tz = pd.Timestamp.now(tz=last_timestamp.tz)
    return last_timestamp.date() >= now_in_exchange_tz.date()


# ---------------------------------------------------------------------------
# Schreiben nach index_prices
# ---------------------------------------------------------------------------
def write_to_db(conn, db_ticker: str, trade_date, ohlcv: dict) -> None:
    sql = """
        INSERT INTO index_prices (Ticker, Date, Open, High, Low, Close, Volume)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            Open = VALUES(Open),
            High = VALUES(High),
            Low = VALUES(Low),
            Close = VALUES(Close),
            Volume = VALUES(Volume)
    """
    with conn.cursor() as cur:
        cur.execute(
            sql,
            (
                db_ticker,
                trade_date,
                ohlcv["open"],
                ohlcv["high"],
                ohlcv["low"],
                ohlcv["close"],
                ohlcv["volume"],
            ),
        )
    conn.commit()


# ---------------------------------------------------------------------------
# Verarbeitung eines einzelnen Tickers
# ---------------------------------------------------------------------------
def process_ticker(conn, ticker_config: dict, force: bool) -> str:
    """
    Verarbeitet einen Ticker komplett (Handelszeiten-Check, Yahoo-Abruf,
    Datums-Check, DB-Schreiben) und gibt einen Status-String zurueck:
    "ok", "skipped_closed", "skipped_no_new_data" oder "error".
    """
    db_ticker = ticker_config["ticker_symbol"]
    yahoo_symbol = ticker_config["yahoo_symbol"]

    if not force and not is_market_hours_now(
        ticker_config["market_open"], ticker_config["market_close"], ticker_config["market_timezone"]
    ):
        log.info(
            "%s: ausserhalb der Handelszeit (%s-%s %s) -> Yahoo-Abfrage wird uebersprungen.",
            db_ticker,
            ticker_config["market_open"],
            ticker_config["market_close"],
            ticker_config["market_timezone"],
        )
        return "skipped_closed"

    try:
        ohlcv = fetch_today_ohlcv(yahoo_symbol)
    except Exception:
        log.exception("%s: Fehler beim Abruf von Yahoo Finance (%s)", db_ticker, yahoo_symbol)
        return "error"

    if ohlcv is None:
        log.warning("%s: keine Daten von Yahoo Finance erhalten (%s)", db_ticker, yahoo_symbol)
        return "skipped_no_new_data"

    last_ts = ohlcv["last_timestamp"]

    if not is_from_today(last_ts):
        log.info(
            "%s: letzter verfuegbarer Kurs ist vom %s (Boersenzeit), nicht von heute -> "
            "kein neuer Tageswert, DB wird nicht beschrieben.",
            db_ticker,
            last_ts,
        )
        return "skipped_no_new_data"

    trade_date = last_ts.date()

    try:
        write_to_db(conn, db_ticker, trade_date, ohlcv)
    except Exception:
        log.exception("%s: Fehler beim Schreiben nach MySQL", db_ticker)
        return "error"

    log.info(
        "%s (%s) geschrieben: Date=%s Open=%.2f High=%.2f Low=%.2f Close=%.2f Volume=%d",
        db_ticker,
        yahoo_symbol,
        trade_date,
        ohlcv["open"],
        ohlcv["high"],
        ohlcv["low"],
        ohlcv["close"],
        ohlcv["volume"],
    )
    return "ok"


# ---------------------------------------------------------------------------
# CLI / main
# ---------------------------------------------------------------------------
def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Holt Tageskurse von Index-Tickern von Yahoo Finance und schreibt sie nach "
            "MySQL. Ohne Angabe eines Tickers werden alle in ticker_symbols aktiven, "
            "vollstaendig konfigurierten Ticker verarbeitet."
        )
    )
    parser.add_argument(
        "ticker",
        nargs="?",
        default=None,
        help=(
            "Optional: nur diesen einen Ticker verarbeiten (ticker_symbol aus "
            "ticker_symbols, z.B. DAX40). Ohne Angabe werden alle konfigurierten "
            "Ticker verarbeitet."
        ),
    )
    parser.add_argument(
        "--defaults-file",
        default="~/.my.cnf",
        help="MySQL-Optionsdatei mit den Zugangsdaten, wie beim mysql-Client (Default: ~/.my.cnf)",
    )
    parser.add_argument(
        "--defaults-group",
        default="client",
        help="Gruppe/Section in der Optionsdatei (Default: client, wie beim mysql-Client)",
    )
    parser.add_argument(
        "--database",
        default=None,
        help="Datenbankname, falls nicht schon per 'database=' in der Optionsdatei gesetzt.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Handelszeiten-Pruefung ignorieren (z.B. zum manuellen Testen ausserhalb der Handelszeit).",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    try:
        conn = get_connection(args.defaults_file, args.defaults_group, args.database)
    except Exception:
        log.exception(
            "Fehler beim Verbinden mit MySQL (Optionsdatei: %s, Gruppe: %s)",
            args.defaults_file,
            args.defaults_group,
        )
        return EXIT_ERROR

    try:
        try:
            ticker_configs = load_ticker_configs(conn, only_ticker=args.ticker)
        except Exception:
            log.exception("Fehler beim Laden von ticker_symbols")
            return EXIT_ERROR

        if not ticker_configs:
            if args.ticker:
                log.error(
                    "Ticker '%s' existiert nicht oder ist nicht vollstaendig konfiguriert "
                    "(active/yahoo_symbol/market_open/market_close/market_timezone).",
                    args.ticker,
                )
                return EXIT_INVALID_TICKER
            log.warning("Keine aktiven/konfigurierten Ticker in ticker_symbols gefunden.")
            return EXIT_NO_NEW_DATA

        statuses = []
        for ticker_config in ticker_configs:
            status = process_ticker(conn, ticker_config, force=args.force)
            statuses.append(status)

    finally:
        conn.close()

    n_ok = statuses.count("ok")
    n_error = statuses.count("error")
    n_skipped = len(statuses) - n_ok - n_error

    log.info(
        "Zusammenfassung: %d verarbeitet, %d geschrieben, %d uebersprungen, %d Fehler",
        len(statuses),
        n_ok,
        n_skipped,
        n_error,
    )

    if n_error > 0:
        return EXIT_ERROR
    if n_ok == 0:
        return EXIT_NO_NEW_DATA
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
