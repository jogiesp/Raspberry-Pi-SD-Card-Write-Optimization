#!/bin/bash
# Erfasst Schreibzugriffe auf die SD-Karte über einen definierten Zeitraum
# und wertet aus, welche Prozesse/Dateien am häufigsten schreiben.

DAUER=${1:-300}   # Dauer in Sekunden, Standard 300s (5 Minuten)
LOGFILE="/tmp/fatrace_$(date +%Y%m%d_%H%M%S).log"

# Prüfen, ob fatrace installiert ist
if ! command -v fatrace &> /dev/null; then
    echo "fatrace ist nicht installiert. Installiere mit:"
    echo "  sudo apt install fatrace"
    exit 1
fi

echo "------------------------------------"
echo "Starte Schreibzugriffs-Mitschnitt für ${DAUER}s..."
echo "Logdatei: $LOGFILE"
echo "------------------------------------"

# fatrace läuft im Hintergrund, nur Schreib-Events (W)
sudo timeout "$DAUER" fatrace -f W > "$LOGFILE" 2>/dev/null

if [ ! -s "$LOGFILE" ]; then
    echo "Keine Schreibzugriffe erfasst (oder Berechtigungsproblem)."
    exit 0
fi

echo ""
echo "===== Top 20 Dateien nach Schreibhäufigkeit ====="
awk '{print $NF}' "$LOGFILE" | sort | uniq -c | sort -rn | head -20

echo ""
echo "===== Top 20 Prozesse nach Schreibhäufigkeit ====="
awk -F'\(' '{print $1}' "$LOGFILE" | sort | uniq -c | sort -rn | head -20

echo ""
echo "===== Gesamtzahl erfasster Schreib-Events: $(wc -l < "$LOGFILE") ====="
echo "Vollständiges Log liegt unter: $LOGFILE"
echo "------------------------------------"
