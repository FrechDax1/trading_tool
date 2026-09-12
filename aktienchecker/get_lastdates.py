# letzte Werte hinzufügen

import yfinance as yf
import os
import mysql.connector
import pandas as pd
import numpy as np
import sys

import argparse

# ArgumentParser erstellen
parser = argparse.ArgumentParser(description="Ticker Symbol und Datum als Parameter")
# Argumente definieren
parser.add_argument("--ende", type=str, help="Endedatum als YYYY-MM-DD")
parser.add_argument("--start", type=str, help="Startdatum als YYYY-MM-DD")
parser.add_argument("--ticker", type=str, help="Tickersymbol, z.B. ^GDAXI, ^NDX, ^GSPC, ^990100-USD-STRD")
# Argumente parsen
args = parser.parse_args()


from datetime import datetime, timedelta

heute = datetime.now().strftime("%Y-%m-%d")
# Argumente auswerten
if args.ende:
    end= args.ende
else:
    end= heute

if args.start:
    start= args.start
else:
    datum_objekt = datetime.strptime(heute, "%Y-%m-%d")
    datum_vor_10_tagen = datum_objekt - timedelta(days=10)
    start = datum_vor_10_tagen.strftime("%Y-%m-%d")

ticker=""
if args.ticker:
  ticker = args.ticker
else:
  print("Kein Tickersysmbol angegeben")
  exit()

print("")
print(f"Update von {start} bis {end} fuer Tickersymbol: {ticker}")

# 1) Daten holen
df = yf.download(ticker, start=start, end=end, auto_adjust=False)
print(df.tail(3))

# 2) Datum als Spalte machen
df = df.reset_index()          # aus dem Index wird die Spalte 'Date'

# Fix: Flatten MultiIndex columns if they exist, to ensure simple column names
if isinstance(df.columns, pd.MultiIndex):
    df.columns = df.columns.get_level_values(0)

# Kontrolle: Spaltennamen
print(df.columns)

# 2) Verbindung zu MySQL
conn = mysql.connector.connect(
    option_files=[os.path.expanduser("~/.my.cnf")]
)
cursor = conn.cursor()

sql = """
INSERT INTO index_prices
(Ticker, Date, Open, High, Low, Close, Volume)
VALUES (%s, %s, %s, %s, %s, %s, %s)
ON DUPLICATE KEY UPDATE
  Open = VALUES(Open),
  High = VALUES(High),
  Low = VALUES(Low),
  Close = VALUES(Close),
  Volume = VALUES(Volume)
"""

# 4) Zeilen bauen – jetzt mit itertuples
rows = []
for row in df.itertuples(index=False):
    rows.append((
        ticker,         # erste Spalte: konstantes Ticker-Symbol
        row.Date,       # jetzt existiert 'Date', weil reset_index() gemacht wurde
        float(row.Open),
        float(row.High),
        float(row.Low),
        float(row.Close),
        int(row.Volume)
    ))

cursor.executemany(sql, rows)
conn.commit()

cursor.close()
conn.close()
conn.close()
