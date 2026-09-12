trading_tool
Sammlung von Batchjobs zur automatisierten Erfassung von Marktdaten in
einer MySQL/MariaDB-Datenbank. Läuft als Cronjobs auf einem Debian-Server.
Enthaltene Batchjobs
Ordner	Skript	Zweck	Doku
`aktienchecker/`	`update_all.sh`	Lädt tägliche Kursdaten (OHLCV) für eine Liste von Indizes/ETFs über yfinance	aktienchecker/README.md
`getData/`	`loadnewCBOEdata2DB.sh`	Lädt die tägliche CBOE Equity Put/Call Ratio der letzten 7 Tage	getData/README.md
Voraussetzungen
Debian (o. ä. Linux) mit `bash`, `cron`, `flock`, `logrotate`
MySQL/MariaDB-Server mit den Tabellen `index_prices` und `market_sentiment`
`default-mysql-client` (für den `mysql`-CLI-Aufruf, siehe `getData`)
Python-virtualenv unter `~/my_python` mit den Paketen `yfinance`,
`mysql-connector-python`, `pandas`, `numpy` (für `aktienchecker`)
Zugangsdaten
Beide Jobs lesen ihre Datenbank-Zugangsdaten aus `~/.my.cnf` im
Home-Verzeichnis des ausführenden Users (Abschnitt `[client]`):
```ini
[client]
host = ...
user = ...
password = ...
database = ...
```
Rechte unbedingt auf `600` setzen (`chmod 600 ~/.my.cnf`). Diese Datei
liegt bewusst außerhalb dieses Repos und wird nicht versioniert.
Cronjobs
```
0 4,7 * * 1-6 /home/carsten/git/trading_tool/aktienchecker/update_all.sh
0 7 * * 1-6   /home/carsten/git/trading_tool/getData/loadnewCBOEdata2DB.sh
0 3 * * *     /usr/sbin/logrotate --state /home/carsten/.cache/logrotate/aktienchecker.state /home/carsten/git/trading_tool/logrotate.conf
```
Logging & Log-Rotation
Beide Skripte schreiben ihr eigenes Log (`update_all.log` bzw.
`cboe_import.log`) direkt in ihr jeweiliges Verzeichnis und schützen sich
per `flock` gegen überlappende Läufe. `logrotate.conf` (im Repo-Root)
sorgt dafür, dass beide Logs einmal im Monat geleert werden (`rotate 0`,
alte Inhalte werden nicht aufgehoben).
Setup auf einem neuen Server
Repo klonen: `git clone git@github.com:FrechDax1/trading_tool.git`
`~/.my.cnf` mit den DB-Zugangsdaten anlegen, `chmod 600` setzen
Python-venv unter `~/my_python` einrichten und Abhängigkeiten installieren
Cronjobs wie oben eintragen (`crontab -e`)
Logrotate-Cronjob eintragen, State-Verzeichnis anlegen
(`mkdir -p ~/.cache/logrotate`)
Sicherheit
Keine Zugangsdaten im Repo (`.my.cnf` liegt außerhalb, `.gitignore`
schließt generierte Dateien wie `*.log`, `.*.lock` und
`ergebnisse_latest.sql` aus)
Vor jedem Commit kurz prüfen, dass keine neuen Dateien mit
Zugangsdaten/Tokens versehentlich mit eingecheckt werden
