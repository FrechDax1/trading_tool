# db-schema

Schema-Dumps (Tabellenstruktur, Views, Trigger, Stored Procedures/Functions,
Events) der Hostinger-Datenbank — versioniert in Git, damit Änderungen
nachvollziehbar und im Notfall wiederherstellbar sind. Enthält **keine
Daten**, nur Struktur.

## Einmaliges Setup

1. `mysql-client` lokal installieren (liefert `mysqldump` und `mysql`), falls
   noch nicht vorhanden:
   - macOS: `brew install mysql-client`
   - Debian/Ubuntu: `sudo apt install mysql-client`
2. Zugangsdaten liegen in deiner MySQL-Optionsdatei, Standardpfad `~/.my.cnf`
   (achte auf den Punkt vor "my" — das ist der MySQL-Standardname, den
   `mysql`/`mysqldump` automatisch einlesen, ohne dass du irgendwas angeben
   musst). Falls deine Datei nicht existiert oder du sie neu anlegen willst:
   ```
   cat > ~/.my.cnf <<'EOF'
   [client]
   host=sql123.hostinger.com
   user=dein_user
   password=dein_passwort
   EOF
   chmod 600 ~/.my.cnf
   ```
   Liegt deine Datei an einem anderen Pfad/Namen, kannst du das dem Script per
   `MYCNF_FILE` mitgeben (siehe unten) — das Script selbst enthält keine
   Zugangsdaten.
3. Falls "Remote MySQL" bei Hostinger nicht freigeschaltet werden soll/kann:
   stattdessen einen SSH-Tunnel über den Webserver aufbauen, auf dem die DB ja
   bereits erreichbar ist, und in der `~/.my.cnf` `host=127.0.0.1` sowie
   `port=3307` eintragen:
   ```
   ssh -N -L 3307:localhost:3306 user@dein-webserver.hostinger.com &
   ```

## Dump erzeugen

```
./dump_schema.sh meine_datenbank
```

Alternativ den Datenbanknamen einmalig in einer `.env` hinterlegen (siehe
`.env.example` — die `.env` enthält jetzt nur noch den DB-Namen, keine
Zugangsdaten mehr) und dann einfach:

```
./dump_schema.sh
```

Falls deine Optionsdatei nicht `~/.my.cnf` heißt:

```
MYCNF_FILE=~/.mycnf ./dump_schema.sh meine_datenbank
```

Erzeugt/aktualisiert im Ordner `schema/`:

- `schema.sql` — Tabellen, Views, Trigger
- `routines.sql` — Stored Procedures & Functions
- `events.sql` — Events (meist leer, falls keine genutzt werden)

Danach wie gewohnt committen:

```
git add schema
git commit -m "Schema-Stand $(date +%F)"
```

So siehst du in der Git-Historie auf einen Blick, wann sich welche
Tabelle/Prozedur geändert hat.

## Restore (im Notfall)

```
mysql DBNAME < schema/schema.sql
mysql DBNAME < schema/routines.sql
mysql DBNAME < schema/events.sql
```

(Zugangsdaten kommen auch hier automatisch aus `~/.my.cnf`.)

## Nächste Schritte (optional, später)

- Das Script per Cron auf dem vzlogger-Server regelmäßig laufen lassen und
  automatisch committen/pushen, statt es nur manuell auszuführen.
- Bei Bedarf auf ein echtes Migrationstool (z. B. Flyway/Liquibase) wechseln,
  sobald ihr aktiv Schema-Änderungen vornehmt und nicht nur den Ist-Zustand
  sichern wollt.

## Sicherheitshinweis

Die Optionsdatei sollte nur für dich lesbar sein: `chmod 600 ~/.my.cnf`.
Weder das Script noch die `.env` enthalten Zugangsdaten, trotzdem bleibt
`.env` in `.gitignore`, damit auch ein versehentlich dort eingetragener
Wert nicht committed wird.
