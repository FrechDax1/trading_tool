import argparse

# ArgumentParser erstellen
parser = argparse.ArgumentParser(description="Ein Beispielskript mit Parametern.")
# Argumente definieren
parser.add_argument("--name", type=str, help="Dein Name")
parser.add_argument("--zahl", type=int, help="Eine Zahl")
parser.add_argument("--flag", action="store_true", help="Ein Flag ohne Wert")
# Argumente parsen
args = parser.parse_args()

# Argumente auswerten
if args.name:
    print("Name:", args.name)
else:
    print("Name missing")
    exit
if args.zahl:
    print("Zahl:", args.zahl)
if args.flag:
    print("Flag ist gesetzt!")

from datetime import datetime, timedelta

# Heutiges Datum als String im Format YYYY-MM-DD
heute = datetime.now().strftime("%Y-%m-%d")
print(heute)

# Heutiges Datum als datetime-Objekt parsen
datum_objekt = datetime.strptime(heute, "%Y-%m-%d")

# 10 Tage zurückrechnen
datum_vor_10_tagen = datum_objekt - timedelta(days=10)

# Datum wieder als String im Format YYYY-MM-DD ausgeben
datum_vor_10_tagen_str = datum_vor_10_tagen.strftime("%Y-%m-%d")
print("Datum vor 10 Tagen:", datum_vor_10_tagen_str)
