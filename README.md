# 💾 Raspberry Pi SD Card Write Optimization

Ein praxiserprobtes, vollständig dokumentiertes Setup zur drastischen Reduktion der SD-Karten-Schreiblast auf einem Raspberry Pi, der **ioBroker**, **InfluxDB**, **Grafana**, **Pi-hole** und **Samba** gleichzeitig betreibt. Ziel: die Lebensdauer der SD-Karte maximieren, ohne Funktionalität, Statistiken oder Stabilität zu opfern.

Kein theoretisches Tuning – jede Änderung wurde vorher/nachher mit [`fatrace`](https://github.com/martinpitt/fatrace) gemessen und belegt.

---

## 🎯 Motivation

SD-Karten sterben an zu vielen kleinen Schreibzyklen, nicht an Datenmenge. Flash-Speicher verschleißt pro **Schreib-/Löschzyklus eines Blocks** (P/E-Cycle) – eine winzige Änderung kann denselben Verschleiß verursachen wie ein großer sequenzieller Schreibvorgang, wenn dafür ein ganzer Block gelöscht und neu beschrieben werden muss. Genau das ist das typische Muster von Diensten wie InfluxDB, Grafana, Pi-hole & Co.: viele kleine, häufige, synchrone Commits.

Dieses Projekt dokumentiert die systematische Methodik dahinter:

1. 🔍 **Messen** statt raten (`fatrace`)
2. 🎯 **Ursache identifizieren** (welche Datei, welcher Mechanismus, welcher Prozess)
3. 🛠️ **Gezielt tunen** (Config-Intervalle, WAL-Modus) oder **verlagern** (Umzug auf USB) oder **eliminieren** (ungenutzte Dienste abschalten)
4. ✅ **A/B-Vergleich** zur Bestätigung – nie eine Änderung ohne Vorher/Nachher-Beweis

---

## 📊 Ergebnisse im Überblick

| Komponente | Vorher | Nachher | Methode |
|---|:---:|:---:|---|
| 🗄️ InfluxDB | 75–82 Writes/Testfenster | **6** | Config-Tuning (wal-fsync-delay, Cache-Snapshots, Monitoring aus) |
| 🕳️ Pi-hole / FTL | Flush alle 60s (dauerhaft) | Flush alle **900s** | `DBinterval` erhöht |
| 📈 Grafana | 23–25 Writes/Testfenster | **0** *(auf SD)* | WAL-Modus + Alerting aus + Token-Rotation gestreckt, komplett auf USB verschoben |
| 🏠 ioBroker | Backup alle 2h, State-Flush alle 60s | Backup alle **6h**, Flush alle **300s** | `iobroker.json`-Tuning + Tuya-Reconnect-Loop behoben |
| 📁 Samba/Winbind | ~84 Writes/900s, 24/7, ohne Nutzen | **0** | Ungenutzten `winbind`-Dienst abgeschaltet |

**Gesamtergebnis:** Von einem System mit ständigen kleinen SD-Schreibzugriffen zu einem Zustand, in dem praktisch nur noch echte, unvermeidbare Nutzdaten geschrieben werden. CPU-Last sank als Nebeneffekt von 40–60 % auf 8–19 %, die CPU-Temperatur von dauerhaft über 40 °C auf dauerhaft unter 40 °C.

---

## 🔧 Messmethodik

Alle Zahlen wurden mit `fatrace` erhoben – ein Tool, das Dateisystem-Schreibzugriffe live pro Prozess/Datei protokolliert:

```bash
sudo timeout 130 fatrace -f W | grep -c <prozessname>
```

**Wichtige Lektionen aus der Praxis:**
- Für belastbare Vergleiche ein Messfenster wählen, das **mindestens einen vollen Intervall-Zyklus** der jeweiligen Komponente abdeckt (z. B. 960s für ein 15-Minuten-Intervall) – ein zu kurzes Fenster kann durch Zufall einen Burst treffen oder verpassen und täuscht ein falsches Bild vor.
- Mit Zeitstempeln messen (`fatrace -t`), um Bursts sauber Zeitpunkten zuzuordnen:
  ```bash
  sudo timeout 3600 fatrace -t -f W 2>/dev/null | grep -i <name> > write_watch.log
  ```
- **Nie zwei Messungen parallel laufen lassen** – sie schreiben sich sonst gegenseitig ins gleiche Log und verfälschen das Ergebnis. Vorher immer prüfen:
  ```bash
  ps aux | grep fatrace
  ```
- Bei Hochrechnungen (Tag/Monat/Jahr) **einmalige Ereignisse rausrechnen** (z. B. ein zufällig ins Messfenster fallender täglicher Backup-Lauf) – sonst verzerrt das die Hochrechnung massiv.
- `lsof <datei>` zeigt, welche Prozesse eine verdächtige Datei offen halten, wenn der Prozessname allein nicht eindeutig ist.

---

## 🗄️ InfluxDB

**Problem:** Standard-`wal-fsync-delay=0s` bedeutet, dass jede einzelne Messung sofort auf Disk committed wird.

**Fix** in `/etc/influxdb/influxdb.conf`:
```ini
[data]
wal-fsync-delay = "10s"
cache-snapshot-memory-size = "128m"
cache-snapshot-write-cold-duration = "30m"
compact-full-write-cold-duration = "24h"

[monitor]
store-enabled = false

[http]
pprof-enabled = false
```

**Warum's wirkt:** Schreibzugriffe werden gebündelt statt einzeln committed.

---

## 🕳️ Pi-hole / FTL

**Problem:** FTL flusht neue DNS-Query-Statistiken standardmäßig jede Minute in die SQLite-WAL-Datei (`pihole-FTL.db-wal`).

**Fix** (Pi-hole v6+, TOML-basierte Config unter `/etc/pihole/pihole.toml`):
```bash
sudo pihole-FTL --config database.DBinterval "900"
sudo systemctl restart pihole-FTL
```

**Warum's wirkt:** Erhöht das Flush-Intervall von 60s auf 900s (15 Min) → Faktor 15 weniger Commits. Trade-off: bis zu 15 Minuten Statistik-Verlust bei einem harten Absturz.

> ⚠️ **Achtung Versionsunterschiede:** Ältere Pi-hole-Versionen (v5) nutzen stattdessen `/etc/pihole/pihole-FTL.conf` mit `DBINTERVAL` in **Minuten**. Mit `pihole -v` die Version prüfen, bevor man Config-Anleitungen aus dem Netz blind übernimmt.

**Bekannter Nebeneffekt:** Zusätzlich zum geplanten Flush kann SQLites **WAL-Autocheckpoint** bei hoher Query-Last unregelmäßig zusätzliche kleine Bursts auslösen (sobald die WAL-Datei eine bestimmte Seitenzahl erreicht). Das lässt sich über FTLs eigene Config nicht direkt steuern – bei uns blieb die Resteffekt-Last aber bei nur ~1 Write/Minute im Schnitt, was den Aufwand für einen kompletten USB-Umzug nicht rechtfertigte.

---

## 📈 Grafana

Der hartnäckigste Kandidat, brauchte drei Maßnahmen plus einen kompletten Umzug:

**1. SQLite-Journal-Modus → WAL**
```bash
sudo crudini --set /etc/grafana/grafana.ini database wal true
```

**2. Ungenutztes Alerting abschalten**
```bash
sudo crudini --set /etc/grafana/grafana.ini unified_alerting enabled false
```

**3. Session-Token-Rotation strecken** (Default: alle 10 Min ein DB-Write)
```bash
sudo crudini --set /etc/grafana/grafana.ini auth token_rotation_interval_minutes "60"
```

**4. Kompletter Umzug der Datenbank auf USB** (der eigentliche Gamechanger)
```bash
sudo systemctl stop grafana-server
sudo rsync -avP /var/lib/grafana/ /media/usbdrive/grafana-data/
sudo chown -R grafana:grafana /media/usbdrive/grafana-data
sudo crudini --set /etc/grafana/grafana.ini paths data "/media/usbdrive/grafana-data"
sudo systemctl edit grafana-server
```
Im Editor:
```ini
[Unit]
RequiresMountsFor=/media/usbdrive
After=media-usbdrive.mount
```
```bash
sudo systemctl daemon-reload
sudo systemctl start grafana-server
```

⚠️ **Wichtig:** `RequiresMountsFor`/`After` verhindert, dass Grafana beim Booten gegen ein leeres Verzeichnis startet, bevor das USB-Laufwerk gemountet ist.

> 💡 **Versionshinweis:** Vor Config-Änderungen immer `grafana-server -v` prüfen und die mitgelieferte `defaults.ini` (meist `/usr/share/grafana/conf/defaults.ini`) nach den aktuell gültigen Keys durchsuchen – Grafana hat zwischen Major-Versionen ganze Config-Sections (z. B. das alte `[alerting]`) entfernt oder umgebaut.

---

## 🏠 ioBroker

Config-Datei: `/opt/iobroker/iobroker-data/iobroker.json`

**Fix:**
```bash
cd /opt/iobroker/iobroker-data
OWNER=$(stat -c '%U:%G' iobroker.json)

sudo sed -i \
  -e 's/"period": 120,/"period": 360,/' \
  -e 's/"intervalMs": 60000,/"intervalMs": 300000,/g' \
  iobroker.json

sudo chown "$OWNER" iobroker.json
sudo systemctl restart iobroker
```

**Was das bewirkt:**
- `objects.backup.period` (2h → 6h): Faktor 3 weniger große Backup-Bursts/Tag (die komprimieren Objects/States in `.jsonl.gz`-Dateien – bei uns der mit Abstand größte Einzelposten in jeder Stundenmessung)
- `throttleFS.intervalMs` (60s → 5 Min, für `objects` und `states`): weniger häufige Flushes der laufenden State-Änderungen in die JSONL-Dateien

**Bonus-Fund – Adapter-Reconnect-Loop:** Ein Tuya-Adapter ohne erreichbares Zielgerät (Smart-Lampe war zwischenzeitlich deaktiviert) startete alle ~60s neu (`scheduled normal terminated and will be restarted`), was `pids.txt` unnötig oft beschrieb. **Fix:** eine Smart-Lampe dauerhaft angeschlossen lassen (muss nicht leuchten) → Loop verschwindet komplett, da der Adapter wieder ein Gerät zum Verbinden hat.

> 💡 **Debugging-Tipp:** Ein exakt gleichmäßiger Zeittakt (z. B. auf die Sekunde jede Minute) deutet meist auf einen festen Schedule hin – ein unregelmäßiger Takt eher auf eine Retry-/Reconnect-Logik nach Fehlern. Beides lässt sich über `mode` im Adapter-Objekt unterscheiden:
> ```bash
> iobroker object get system.adapter.<name> | grep -oE '"mode":\s*"[^"]*"'
> ```
> `daemon` = dauerhaft laufender Prozess mit interner Logik, `schedule` = extern getaktet.

---

## 📁 Samba / Winbind

**Problem:** Der `winbind`-Dienst lief permanent mit, obwohl gar keine Active-Directory-Domäne im Einsatz war (nur `workgroup`-Setup). Er verursachte dauerhafte Schreibzugriffe auf mehrere `.tdb`-Dateien (`passdb.tdb`, `secrets.tdb`, `group_mapping.tdb`, `account_policy.tdb`) – **ganz ohne aktive SMB-Verbindungen** (bestätigt über `smbstatus`, das "No locked files" und leere Sessions zeigte).

**Diagnose:**
```bash
sudo smbstatus                                    # keine aktiven Clients?
sudo lsof /var/lib/samba/private/passdb.tdb        # wer hat die Datei offen?
grep -E "^\s*(security|workgroup|realm)" /etc/samba/smb.conf   # Domain-Mitgliedschaft?
```
Wenn `smbstatus` keine Clients zeigt, aber trotzdem geschrieben wird, UND `smb.conf` kein `realm`/`security = ads|domain` hat → Winbind ist wahrscheinlich unnötig.

**Fix:**
```bash
sudo systemctl stop winbind
sudo systemctl disable winbind
```

**Warum das sicher ist:** Winbind übersetzt nur Windows-Domain-Benutzer/-Gruppen in lokale Unix-IDs. Ohne Domain hat es schlicht nichts zu tun außer sich selbst zu verwalten. Normale SMB-Dateifreigaben (`smbd`, `nmbd`) laufen komplett unabhängig weiter.

**Verifiziert:** SMB-Zugriff von Client-Geräten funktionierte danach unverändert.

---

## ⚠️ Hinweise & Trade-offs

- Alle Änderungen reduzieren die **Persistenz-Frequenz**, nicht die Funktionalität. Bei einem Absturz/Stromausfall geht der jeweils letzte Intervall an Statistikdaten verloren (Sekunden bis Minuten, keine strukturellen Daten).
- Die Grafana-Token-Rotation von 10 auf 60 Minuten zu strecken erhöht das Zeitfenster für einen gestohlenen Session-Token — nur empfehlenswert für Instanzen, die **nicht** öffentlich im Internet erreichbar sind.
- Ein Symlink-Umzug (wie theoretisch bei Pi-hole überlegt) ist fragiler als eine native Config-Option: Falls ein Dienst-Update die Datei aktiv neu anlegt statt den Symlink zu nutzen, landet sie wieder auf der SD-Karte. Nach größeren Updates lohnt ein Blick mit `ls -la`.
- Vor jeder Config-Änderung: **Backup!**
  ```bash
  sudo cp <config-datei> <config-datei>.bak-$(date +%Y%m%d-%H%M%S)
  ```
- Nicht jede Komponente muss bis zum letzten Prozent optimiert werden – bei Restlasten im Bereich von 1 Write/Minute (wie am Ende bei Pi-hole) übersteigt der Aufwand eines weiteren Umzugs oft den Nutzen.

---

## 🖥️ Umgebung

- Raspberry Pi (Debian 13 / Trixie)
- Pi-hole v6.4.3 / FTL v6.7
- Grafana v13.2.2
- InfluxDB (1.x)
- ioBroker (js-controller, jsonl-DB)
- Samba 4.22 (Workgroup, kein AD)

---

## 📝 Lizenz

MIT — nutz es, wie du magst. 🎉
