#!/bin/bash

# --- Konfiguration ---
start_date="2024-01-01"
end_date="2026-09-03"
output_file="ergebnisse.csv"
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
            echo "${current},${val}" >> "$output_file"
        else
            echo "Kein Wert für $current gefunden."
        fi
    fi

    # Einen Tag weiterzählen
    current=$(date -d "$current + 1 day" +%Y-%m-%d)
done

echo "Fertig! Ergebnisse wurden in '$output_file' gespeichert."
