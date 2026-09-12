aktienchecker
Lädt für eine feste Liste von Ticker-Symbolen die aktuellen historischen
Tageskurse (OHLCV) über yfinance und
schreibt sie per Upsert in die MySQL-Tabelle `index_prices`.
Dateien
Datei	Zweck
`update_all.sh`	Cron-Einstiegspunkt: aktiviert das venv, schleift über alle Ticker, ruft `get_lastdates.py` je Ticker auf
`get_lastdates.py`	Lädt Kursdaten für einen Ticker via yfinance und schreibt sie in die Datenbank
Ablauf von `update_all.sh`
Wechselt ins eigene Skriptverzeichnis, setzt `PATH` explizit
Leitet die komplette Ausgabe nach `update_all.log` um
Verhindert per `flock` parallele Läufe (`.update_all.lock`)
Aktiviert das Python-venv unter `~/my_python`
Ruft für jeden Ticker in der Liste `tickers=(...)` `get_lastdates.py --ticker "<Symbol>"` auf
Zählt fehlgeschlagene Ticker-Läufe mit; beendet sich am Ende mit
Exit-Code `1`, falls mindestens einer fehlgeschlagen ist
Ein einzelner fehlgeschlagener Ticker bricht den Lauf nicht ab – die
übrigen Ticker werden trotzdem abgearbeitet.
Ticker-Liste anpassen
Die Liste steht direkt im Skript:
```bash
tickers=(
    "^GDAXI"
    "^GSPC"
    "^NDX"
    "^990100-USD-STRD"
    "^VIX"
    "^N225"
    "^RUT"
    "^STOXX"
    "EEM"
    "AAXJ"
)
```
Neuen Ticker hinzufügen: einfach eine weitere Zeile in der Liste ergänzen.
`get_lastdates.py`
```
python get_lastdates.py --ticker "^GDAXI" [--start YYYY-MM-DD] [--ende YYYY-MM-DD]
```
Parameter	Pflicht	Standard	Bedeutung
`--ticker`	ja	–	yfinance-Tickersymbol
`--start`	nein	heute − 10 Tage	Beginn des abzufragenden Zeitraums
`--ende`	nein	heute	Ende des abzufragenden Zeitraums
Lädt die Kursdaten über `yf.download(...)` und schreibt sie per
`INSERT ... ON DUPLICATE KEY UPDATE` in die Tabelle `index_prices`
(Spalten `Ticker, Date, Open, High, Low, Close, Volume`). Bereits
vorhandene Datensätze (gleicher Ticker + Datum) werden dabei
aktualisiert statt dupliziert – dafür muss die Tabelle einen
`UNIQUE`- bzw. `PRIMARY KEY` auf `(Ticker, Date)` besitzen.
Zugangsdaten kommen wie beim CBOE-Job aus `~/.my.cnf`
(`mysql.connector.connect(option_files=[os.path.expanduser("~/.my.cnf")])`).
Bekannte Besonderheiten
yfinance behandelt das `end`-Datum als exklusiv – der aktuelle Tag
wird je nach Uhrzeit daher erst mit dem nächsten Lauf vollständig
erfasst. Da `update_all.sh` zweimal täglich (4 und 7 Uhr) läuft und der
Standard-Zeitraum 10 Tage zurückreicht, gleicht sich das über die
nächsten Läufe automatisch aus.
Ein fehlender oder ungültiger Ticker bei yfinance liefert einen leeren
DataFrame zurück; das wird aktuell nicht separat abgefangen, sondern
führt einfach zu einem `executemany`-Aufruf ohne Zeilen (kein Fehler,
aber auch kein Hinweis im Log).
Manueller Test
```bash
cd ~/git/trading_tool/aktienchecker
source ~/my_python/bin/activate
python get_lastdates.py --ticker "^GDAXI"
```
Cron
```
0 4,7 * * 1-6 /home/carsten/git/trading_tool/aktienchecker/update_all.sh
```
Logs
`update_all.log` im selben Verzeichnis (Rotation über `../logrotate.conf`)
`.update_all.lock` als reine Lock-Datei (kein Loginhalt)
