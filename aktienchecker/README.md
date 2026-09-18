# aktienchecker

Lädt für eine über die Tabelle `ticker_symbols` gesteuerte Liste von
Ticker-Symbolen die aktuellen Tageskurse (Open/High/Low/Close/Volume) via
[yfinance](https://pypi.org/project/yfinance/) und schreibt sie per Upsert
in die MySQL-Tabelle `index_prices`.

> **Zwei komplementäre Systeme, kein Ersatz:** `update_all_2.sh` /
> `get_lastdates.py` läuft weiterhin **nachts** und lädt dabei rückwirkend
> die letzten Tage neu (10-Tage-
> Rückblick, wegen yfinance's exklusivem `end`-Datum) - das stellt sicher,
> dass die Werte des Vortages final korrekt in `index_prices` stehen.
> `run_hourly.sh` / `index_prices.py` (dieses Setup) läuft zusätzlich
> **tagsüber stündlich** und schreibt nur den **laufenden Handelstag**
> als Intraday-Snapshot, der im Tagesverlauf mehrfach aktualisiert wird.
> Beide schreiben in dieselbe Tabelle `index_prices` per
> `INSERT ... ON DUPLICATE KEY UPDATE` auf `(Ticker, Date)` - der jeweils
> letzte Lauf gewinnt für den betroffenen Tag, Konflikte gibt es keine,
> solange beide Jobs nicht exakt gleichzeitig für denselben Ticker/Tag
> schreiben.

## Dateien

| Datei | Zweck |
|---|---|
| `run_hourly.sh` | Cron-Einstiegspunkt: Lock gegen parallele Läufe, holt aktive Ticker aus `ticker_symbols`, ruft `index_prices.py` je Ticker auf, aktualisiert bei Erfolg die Indikatoren |
| `index_prices.py` | Lädt Kursdaten für EINEN Ticker (oder ohne Parameter: alle konfigurierten) via yfinance und schreibt sie in `index_prices` |
| `schema_ticker_symbols.sql` | Migrationsskript: erweitert `ticker_symbols` um `yahoo_symbol`/`market_open`/`market_close`/`market_timezone`/`active`, befüllt die Basis-Ticker |
| `schema_ticker_symbols_additions.sql` | Ergänzt Russell 2000, VIX, AAXJ, EEM |
| `requirements.txt` | Python-Abhängigkeiten (yfinance, pandas, PyMySQL, tzdata) |
| `update_all_2.sh` / `get_lastdates.py` | **Aktiv, Cron-tauglich** (Lock + eigenes Log). Nächtlicher Backfill-Lauf, siehe eigener Abschnitt unten. |
| `update_all.sh` | **Veraltet, nicht mehr per Cron aktiv** - alte Vorgängerversion ohne Lock/Logging, durch `update_all_2.sh` ersetzt. Ggf. kann sie entfernt werden. |

## Ticker-Liste kommt aus der Datenbank, nicht mehr aus dem Skript

Anders als bei `update_all_2.sh` (feste `tickers=(...)`-Liste direkt im
Skript) steht die Ticker-Liste für `run_hourly.sh` in der Tabelle
`ticker_symbols`. `run_hourly.sh` verarbeitet automatisch **alle** Zeilen,
bei denen:

- `active = 1`
- `yahoo_symbol`, `market_open`, `market_close`, `market_timezone` alle
  gesetzt sind

`ticker_symbol` (Primärschlüssel) entspricht bei uns direkt dem
Yahoo-Finance-Symbol (z.B. `^GDAXI`, `^990100-USD-STRD`) - genau wie im
Vorgänger-System. Die separate `yahoo_symbol`-Spalte wird redundant
mitgeführt, aktuell also identisch zu `ticker_symbol`.

Aktuell konfiguriert:

| Ticker (= yahoo_symbol) | Beschreibung | Handelszeit (lokal) | Zeitzone |
|---|---|---|---|
| `^GDAXI` | DAX 40 | 09:00–17:30 | `Europe/Berlin` |
| `^NDX` | Nasdaq 100 | 09:30–16:00 | `America/New_York` |
| `^GSPC` | S&P 500 | 09:30–16:00 | `America/New_York` |
| `^990100-USD-STRD` | MSCI World (Index) | 09:30–16:00 | `America/New_York` |
| `^N225` | Nikkei 225 | 09:00–15:00 | `Asia/Tokyo` |
| `^RUT` | Russell 2000 | 09:30–16:00 | `America/New_York` |
| `^VIX` | CBOE Volatility Index | 09:15–16:15 | `America/New_York` |
| `AAXJ` | MSCI AC Asia ex Japan (Proxy-ETF) | 09:30–16:00 | `America/New_York` |
| `EEM` | MSCI Emerging Markets (Proxy-ETF) | 09:30–16:00 | `America/New_York` |

`^STOXX` (Euro Stoxx) war im Vorgänger-System enthalten, ist aktuell
**bewusst nicht** konfiguriert.

Neuen Ticker hinzufügen: Zeile in `ticker_symbols` einfügen/updaten (siehe
`schema_ticker_symbols*.sql` als Vorlage) - **keine Code-Änderung nötig.**

## Ablauf von `run_hourly.sh`

1. **Lock** über `flock` (`.run_hourly.lock`) - verhindert überlappende
   Läufe. Läuft bereits ein Durchlauf, bricht der neue sofort mit
   Exit-Code `4` ab, ohne etwas anzufassen.
2. Prüft, ob der venv-Python (`$PYTHON`, aktuell
   `/home/carsten/my_python/bin/python`) und `index_prices.py` existieren.
3. Liest per `mysql -N -B -e "..."` alle aktiven, vollständig
   konfigurierten Ticker aus `ticker_symbols`.
4. Ruft pro Ticker `"$PYTHON" index_prices.py "<ticker>"` auf.
5. Bei Exit-Code `0` (Kurse geschrieben):
   ```sql
   CALL sp_approx_indicators_today('<ticker>', CURDATE(), 150);
   ```
   aktualisiert die Indikatoren für genau diesen Ticker.
6. Sammelt den Status über alle Ticker und gibt einen Gesamt-Exit-Code
   zurück.

## `index_prices.py`

```bash
python index_prices.py                   # alle aktiven/konfigurierten Ticker
python index_prices.py "^GDAXI"          # nur diesen einen Ticker
python index_prices.py "^GDAXI" --force  # Handelszeiten-Prüfung ignorieren (manueller Test)
```

- Prüft zuerst, ob die zugehörige Börse **gerade** offen hat (aus
  `ticker_symbols`, ausgewertet in der jeweiligen Börsen-Zeitzone via
  `zoneinfo`, Mo–Fr) - außerhalb der Handelszeit wird Yahoo gar nicht erst
  angefragt.
- Holt `history(period="1d", interval="5m")` und aggregiert zu
  Open/High/Low/Close/Volume des laufenden Handelstags.
- Schreibt nur, wenn die letzte verfügbare Kerze tatsächlich von „heute"
  ist (Börsenzeit) - liefert Yahoo noch den Schlusskurs von gestern
  (Börse noch nicht offen), wird **nichts** geschrieben.
- `INSERT ... ON DUPLICATE KEY UPDATE` auf `(Ticker, Date)` - mehrfache
  Läufe am selben Tag aktualisieren den Datensatz, statt Duplikate zu
  erzeugen.

MySQL-Zugangsdaten kommen wie beim `mysql`-Client aus `~/.my.cnf`
(`pymysql.connect(read_default_file="~/.my.cnf", read_default_group="client")`)
- **keine eigene `config.ini` mehr.**

## Exit-Codes

**`index_prices.py`**

| Code | Bedeutung |
|---|---|
| `0` | OK - Kurse geschrieben |
| `1` | Fehler (DB-Verbindung, Yahoo-Abruf, Schreibfehler) |
| `2` | Kein neuer Tageswert (Börse zu / kein neuer Kurs) - kein Fehler |
| `3` | Ticker existiert nicht / nicht vollständig konfiguriert |

**`run_hourly.sh`**

| Code | Bedeutung |
|---|---|
| `0` | OK - mind. ein Ticker geschrieben, keine Fehler |
| `1` | Fehler bei mind. einem Ticker (Kursabruf, Schreiben, Indikatoren) |
| `2` | nichts geschrieben, aber auch kein Fehler (Börsen zu / keine neuen Werte) |
| `4` | Skript läuft bereits (Lock nicht erhalten) - kein neuer Durchlauf gestartet |

**`update_all_2.sh`**

| Code | Bedeutung |
|---|---|
| `0` | OK - alle Ticker erfolgreich |
| `1` | mind. ein Ticker fehlgeschlagen **oder** Skript läuft bereits (Lock) - beide Fälle sind hier nicht unterscheidbar, anders als bei `run_hourly.sh` |

## Cron

```cron
30 7-21 * * 1-5 /home/carsten/git/trading_tool/aktienchecker/run_hourly.sh >> /home/carsten/git/trading_tool/aktienchecker/run_hourly.log 2>&1
```

Läuft stündlich zur Minute 30, 7–21 Uhr **UTC** (Server steht auf UTC,
Debian-Cron unterstützt kein `CRON_TZ`), Mo–Fr. Das entspricht
**8:30–22:30 Uhr Berlin-Winterzeit** bzw. **9:30–23:30 Uhr
Berlin-Sommerzeit** - deckt DAX, US-Werte (NDX/SPX/RUT/VIX) und die
Proxy-ETFs (AAXJ/EEM) ganzjährig ab, inklusive der kurzen Wochen mit
versetzter US-/EU-Sommerzeit-Umstellung. Keine halbjährliche Anpassung
nötig.

**`^N225` (Nikkei) wird mit diesem Fenster NICHT erfasst** - Handelszeit
2:00–8:00 Uhr Berlin-Zeit liegt außerhalb des Cron-Fensters. Bewusste
Entscheidung, kein Bug.

## Nächtlicher Backfill: `update_all_2.sh` / `get_lastdates.py`

`update_all.sh` ist die **alte, nicht mehr per Cron laufende Version**.
Aktiv ist `update_all_2.sh` (Cron-tauglich, mit eigenem Lock und
Logging) - läuft weiterhin als eigener, separater Cron-Job, vermutlich
mit unverändertem Zeitplan, jetzt aber ohne Log-Umleitung in der
Crontab-Zeile selbst (das Skript leitet sein Log intern per
`exec >> "$LOG_FILE" 2>&1` um):

```cron
0 4,7 * * 1-6 /home/carsten/git/trading_tool/aktienchecker/update_all_2.sh
```

*(Zeitplan wie im ursprünglichen Setup übernommen - bitte den tatsächlichen
Crontab-Eintrag gegenprüfen.)*

Ablauf von `update_all_2.sh`:

1. Setzt `PATH` explizit (`/usr/local/bin:/usr/bin:/bin`) - robust
   gegenüber Cron's minimalem Standard-`PATH`.
2. Wechselt ins eigene Skriptverzeichnis (`readlink -f` löst auch
   Symlinks auf).
3. Leitet die komplette Ausgabe selbst nach `update_all.log` um
   (`exec >> ... 2>&1`).
4. **Lock** über `flock` (`.update_all.lock`, feste FD `200`) - verhindert
   parallele Läufe; ist bereits ein Lauf aktiv, wird das geloggt und mit
   Exit-Code `1` abgebrochen (anders als bei `run_hourly.sh` gibt es hier
   **keinen eigenen** Exit-Code für "läuft bereits" - beides landet auf
   `1`).
5. Aktiviert das venv (`source $VENV_DIR/bin/activate`) und ruft danach
   trotzdem `"$PYTHON"` (voller Pfad) explizit auf - doppelt hält
   besser, aber im Grunde redundant.
6. Läuft über die feste Ticker-Liste `tickers=(...)` im Skript (**inkl.
   `^STOXX`**, das aktuell **nicht** in `ticker_symbols` steht) und ruft
   je Ticker `get_lastdates.py --ticker "<Symbol>"` auf. Lädt dabei einen
   10-Tage-Rückblick (Standard von `get_lastdates.py`) und schreibt per
   `INSERT ... ON DUPLICATE KEY UPDATE` - stellt sicher, dass auch Werte,
   die `index_prices.py` tagsüber ggf. nur unvollständig erfasst hat
   (z.B. bei Ausfällen), spätestens am nächsten Morgen final korrekt sind.
7. Zählt fehlgeschlagene Ticker mit; beendet sich mit Exit-Code `1`, falls
   mindestens einer fehlgeschlagen ist, sonst `0`. Ein fehlgeschlagener
   Ticker bricht den Lauf nicht ab - die übrigen werden trotzdem
   abgearbeitet.

**Wichtig:** `tickers=(...)` in `update_all_2.sh` und die Tabelle
`ticker_symbols` (für `run_hourly.sh`) sind **zwei komplett unabhängige
Listen** - siehe „Bekannte Einschränkungen" unten.

Zugangsdaten kommen wie überall aus `~/.my.cnf`.

## Logs & Rotation

- `run_hourly.log` (Intraday, dieses Setup) und `update_all.log`
  (nächtlicher Backfill, `update_all_2.sh`) im selben Verzeichnis
- `.run_hourly.lock` bzw. `.update_all.lock` als reine Lock-Dateien (kein
  Loginhalt, von `flock` verwaltet, kein manuelles Aufräumen nötig)
- Rotation über `../logrotate.conf` - **bereits aktualisiert**, erfasst
  neben `update_all.log` und `run_hourly.log` auch die Logs der
  Nachbarprojekte `aaii_extractor` und `getData` im selben Repo
  (`trading_tool`). Konfiguration: monatliche Rotation, nur 1 alte
  Version behalten (`rotate 1`), `missingok`, `dateext`.

## Manueller Test

```bash
cd ~/git/trading_tool/aktienchecker
/home/carsten/my_python/bin/python index_prices.py "^GDAXI" --force
```

## Bekannte Einschränkungen / TODOs

- **`index_prices.Ticker` ist `varchar(10)`** - reicht für die meisten
  Symbole, aber **nicht** für `^990100-USD-STRD` (17 Zeichen, MSCI World)!
  Der INSERT für diesen Ticker schlägt damit fehl, solange die Spalte
  nicht vergrößert wird:
  ```sql
  ALTER TABLE index_prices MODIFY Ticker VARCHAR(20);
  ```
- `index_prices.py` selbst lädt keine verpassten Tage nach - das
  übernimmt der nächtliche `get_lastdates.py`-Lauf mit seinem
  10-Tage-Rückblick. Fällt auch dieser mehrere Tage am Stück aus, ist
  trotzdem ein manuelles Nachtragen nötig (Rückblick ist auf 10 Tage
  begrenzt).
- **Zwei unabhängige Ticker-Listen:** `ticker_symbols` (für
  `run_hourly.sh`) und das feste `tickers=(...)`-Array in
  `update_all_2.sh` laufen aktuell getrennt. Ein neuer Ticker muss ggf. an beiden Stellen
  ergänzt werden, sonst bekommt er tagsüber Intraday-Updates, aber keinen
  nächtlichen Backfill (oder umgekehrt).
- `^VIX` hat eine abweichende Handelszeit (9:15–16:15 ET statt der
  üblichen 9:30–16:00 ET).
- `AAXJ`/`EEM` sind ETF-Proxys, kein reiner Index - haben echtes
  Handelsvolumen (im Gegensatz zu `^GDAXI`/`^NDX`/`^GSPC`/`^RUT`/`^VIX`/
  `^N225`, wo `Volume` meist `0` ist).
- Die Mittagspause der Tokioter Börse (11:30–12:30 JST) wird im
  Handelszeitfenster von `^N225` nicht separat berücksichtigt -
  unschädlich, da Yahoo während der Pause einfach den Kurs von davor
  zurückgibt.