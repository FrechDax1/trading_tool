#!/bin/bash

# --- Konfiguration ---
start_date=$(date -d "7 days ago" +%Y-%m-%d)
end_date=$(date +%Y-%m-%d)
output_file="ergebnisse_latest.csv"
source="CBOE"
symbol="EQUITY_PC"

# neue Datei anfangen
rm $output_file

base_url="https://www.cboe.com/markets/us/options/market-statistics/daily"  # Ersetze dies mit deiner echten Basis-URL

current="$start_date"

while [ "$(date -d "$current" +%Y%m%d)" -le "$(date -d "$end_date" +%Y%m%d)" ]; do
    # Wochentag ermitteln (1 = Montag, 6 = Samstag, 7 = Sonntag)
    day_of_week=$(date -d "$current" +%u)

    # Nur Werktage verarbeiten (Montag bis Freitag)
    if [ "$day_of_week" -lt 6 ]; then
        echo "Verarbeite $current..."

        # 1. Daten per wget laden (-q für quiet, -O - leitet Ausgabe an Pipe weiter)
        # 2. Per sed den Wert filtern
        val=$(wget -q -O - "${base_url}?dt=${current}" | sed -En 's/.*EQUITY PUT\/CALL RATIO\\",\\"value\\":\\"([0-9.]+)\\"\}.*/\1/p')

        # Prüfen, ob ein Wert gefunden wurde
        if [ -n "$val" ]; then
            # Im CSV-Format an die Datei anhängen
            echo "${current},${val}" 
            #echo "INSERT INTO market_sentiment (date, source, symbol, value) VALUES ('${current}', '${source}', '${symbol}', ${val}) ON DUPLICATE KEY UPDATE value = VALUES(value);" \
            #| mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME"
            echo "INSERT INTO market_sentiment (date, source, symbol, value) VALUES ('${current}', '${source}', '${symbol}', ${val}) ON DUPLICATE KEY UPDATE value = VALUES(value);"  >> "$output_file"
        else
            echo "Kein Wert für $current gefunden."
        fi
    fi

    # Einen Tag weiterzählen
    current=$(date -d "$current + 1 day" +%Y-%m-%d)
done

echo "Fertig! Ergebnisse wurden in '$output_file' gespeichert."
mysql < $output_file
