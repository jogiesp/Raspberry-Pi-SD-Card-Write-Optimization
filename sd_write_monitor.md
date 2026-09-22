# 🔍 sd_write_monitor.sh

Kleines Diagnose-Skript, das während der gesamten Optimierung in diesem Projekt als Mess-Werkzeug diente. Es ist ein Wrapper um [`fatrace`](https://github.com/martinpitt/fatrace) und beantwortet die zentrale Frage jeder SD-Karten-Optimierung: **Wer schreibt gerade wie oft wohin?**

## Verwendung

```bash
./sd_write_monitor.sh <sekunden>
```

Beispiel – 15 Minuten mitschneiden:
```bash
./sd_write_monitor.sh 900
```

## Was es macht

1. Startet `fatrace` für die angegebene Dauer und protokolliert alle Schreibzugriffe (`-f W`) systemweit
2. Wertet das Log am Ende automatisch aus und zeigt zwei Ranglisten:
   - **Top 20 Dateien** nach Schreibhäufigkeit
   - **Top 20 Prozesse** nach Schreibhäufigkeit
3. Gibt die Gesamtzahl erfasster Schreib-Events aus
4. Speichert das vollständige Rohlog unter `/tmp/fatrace_<timestamp>.log` für spätere Detailanalyse (z. B. um Bursts zeitlich einzugrenzen)

## Warum das der richtige erste Schritt ist

Ohne eine Rangliste wie diese tunt man nach Vermutung statt nach Beweis – man könnte tagelang an einer Komponente schrauben, die gar nicht das eigentliche Problem ist. Das Skript liefert in wenigen Minuten eine klare Priorisierung: Womit lohnt es sich anzufangen?

**Praxis-Tipp aus diesem Projekt:** Kurze Messfenster (60s) eignen sich gut für einen schnellen Überblick, können aber bei Diensten mit langen Intervallen (z. B. alle 15 Minuten) täuschen – ein Burst wird entweder komplett erfasst oder komplett verpasst. Für belastbare Vergleiche vor/nach einer Optimierung lieber ein Fenster wählen, das mindestens einen vollen Intervall-Zyklus abdeckt (siehe Hauptdoku).

## Voraussetzung

```bash
sudo apt install -y fatrace
```

Das Skript selbst braucht `sudo`-Rechte, da `fatrace` systemweite Dateisystem-Ereignisse nur mit erhöhten Rechten mitlesen kann.
