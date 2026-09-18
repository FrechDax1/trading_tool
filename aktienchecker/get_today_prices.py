import yfinance as yf
import argparse


# ArgumentParser erstellen
parser = argparse.ArgumentParser(description="Ticker Symbol")
# Argumente definieren
parser.add_argument("--ticker", type=str, help="Tickersymbol, z.B. ^GDAXI, ^NDX, ^GSPC, ^990100-USD-STRD")
# Argumente parsen
args = parser.parse_args()

ticker=""
if args.ticker:
  ticker = args.ticker
else:
  print("Kein Tickersysmbol angegeben")
  exit()

t = yf.Ticker(ticker)
fi = t.fast_info

print("Open:", fi["open"])
print("Day High:", fi["dayHigh"])
print("Day Low:", fi["dayLow"])
print("Last Price:", fi["lastPrice"])


#  history auslesen
t = yf.Ticker(ticker)
hist = t.history(period="1d", interval="5m")

if hist.empty:
    print(f"Keine Daten für {symbol} verfügbar (Markt evtl. geschlossen).")
else:
    open_today = hist["Open"].iloc[0]      # erster Wert des Tages
    high_today = hist["High"].max()
    low_today = hist["Low"].min()
    last_row = hist.iloc[-1]
    last_price = last_row["Close"]
    last_time = hist.index[-1]
    volume_today = hist["Volume"].sum()

    print(f"Index:        {ticker}")
    print(f"Open (Tag):   {open_today:.2f}")
    print(f"High (Tag):   {high_today:.2f}")
    print(f"Low (Tag):    {low_today:.2f}")
    print(f"Letzter Preis:{last_price:.2f}")
    print(f"Zeitpunkt:    {last_time}")
    print(f"Volumen (Tag):{volume_today:.0f}")
