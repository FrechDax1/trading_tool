getData – CBOE Equity Put/Call Ratio Import
Lädt täglich die CBOE Equity Put/Call Ratio der letzten 7 Kalendertage
(werktags) von der CBOE-Website und schreibt neue bzw. geänderte Werte in
die MySQL-Tabelle `market_sentiment`.
Datei
Datei	Zweck
`loadnewCBOEdata2DB.sh`	Vollständiger Batchjob: Download, Parsen, Import
Ablauf
Wechselt ins eigene Skriptverzeichnis, setzt `PATH` explizit
Leitet die komplette Ausgabe nach `cboe_import.log` um
Verhindert per `flock` parallele Läufe (`.cboe_import.lock`)
Iteriert über die letzten 7 Kalendertage bis heute, überspringt
Sonntage
Lädt pro Tag `https://www.cboe.com/.../daily?dt=<Datum>` per `wget`
und extrahiert den Wert der "Equity Put/Call Ratio" per `sed`
Schreibt gefundene Werte als `INSERT ... ON DUPLICATE KEY UPDATE`
in eine Zwischen-SQL-Datei (`ergebnisse_latest.sql`)
Spielt die gesammelte SQL-Datei am Ende per
`mysql < ergebnisse_latest.sql` in die Datenbank ein
Datenbank-Schema
```sql
INSERT INTO market_sentiment (date, source, symbol, value)
VALUES (?, ?, ?, ?)
ON DUPLICATE KEY UPDATE value = VALUES(value);
```
`source` = `CBOE`
`symbol` = `EQUITY_PC`
Die Tabelle braucht einen `UNIQUE`- bzw. `PRIMARY KEY` auf
`(date, source, symbol)`, damit der Upsert korrekt funktioniert.
Konfiguration
Am Kopf des Skripts:
```bash
source_name="CBOE"
symbol="EQUITY_PC"
base_url="https://www.cboe.com/markets/us/options/market-statistics/daily"
```
Zugangsdaten für den `mysql`-Aufruf kommen aus `~/.my.cnf`.
Manueller Test
```bash
cd ~/git/trading_tool/getData
./loadnewCBOEdata2DB.sh
tail -f cboe_import.log
```
Cron
```
0 7 * * 1-6 /home/carsten/git/trading_tool/getData/loadnewCBOEdata2DB.sh
```
Logs
`cboe_import.log` im selben Verzeichnis (Rotation über `../logrotate.conf`)
`.cboe_import.lock` als reine Lock-Datei (kein Loginhalt)
`ergebnisse_latest.sql` als temporäre Zwischendatei – wird bei jedem
Lauf neu erzeugt und ist nicht versioniert (siehe `.gitignore`)
