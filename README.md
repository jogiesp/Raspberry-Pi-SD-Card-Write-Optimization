# 💾 Raspberry Pi SD Card Write Optimization

Ein praxiserprobtes Setup zur drastischen Reduktion der SD-Karten-Schreiblast auf einem Raspberry Pi, der **ioBroker**, **InfluxDB**, **Grafana** und **Pi-hole** gleichzeitig betreibt. Ziel: die Lebensdauer der SD-Karte maximieren, ohne Funktionalität, Statistiken oder Stabilität zu opfern.

Kein theoretisches Tuning – jede Änderung wurde vorher/nachher mit [`fatrace`](https://github.com/martinpitt/fatrace) gemessen und belegt.

---

## 🎯 Motivation

SD-Karten sterben an zu vielen kleinen Schreibzyklen, nicht an Datenmenge. Dienste wie InfluxDB, Grafana und Pi-hole schreiben standardmäßig sehr häufig kleine Datenmengen (WAL-Flushes, Session-Rotation, Journal-Commits) – meist deutlich öfter, als es für die eigentliche Funktion nötig wäre.

Dieses Projekt dokumentiert, wie man das systematisch aufspürt und entschärft:

1. 🔍 **Messen** statt raten (`fatrace`)
2. 🎯 **Ursache identifizieren** (welche Datei, welcher Mechanismus)
3. 🛠️ **Gezielt tunen** (Config-Intervalle, WAL-Modus) oder **verlagern** (Umzug auf USB)
4. ✅ **A/B-Vergleich** zur Bestätigung

---

## 📊 Ergebnisse im Überblick

| Komponente  | Vorher (Writes/Messfenster) | Nachher | Methode |
|-------------|:---:|:---:|---------|
| 🗄️ InfluxDB | 75–82 | **6** | `influxdb.conf`-Tuning (WAL-Fsync-Delay, Cache-Snapshots, Monitoring aus) |
| 🕳️ Pi-hole / FTL | 6–8 (im Ranking; ~20 Writes/130s auf Dateiebene) | **0** | `DBinterval` von 60s auf 900s erhöht |
| 📈 Grafana | 23–25 | **0** *(auf SD)* | WAL-Modus + Alerting aus + Token-Rotation gestreckt, danach komplett auf USB verschoben |

**Gesamtergebnis:** Von einem System, das dauerhaft mehrfach pro Minute auf die SD-Karte schrieb, zu einem Zustand, in dem praktisch nur noch echte, unvermeidbare Nutzdaten geschrieben werden.

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

**Warum's wirkt:** Schreibzugriffe werden gebündelt statt einzeln committed – analog zu einem Batch-Write statt Single-Insert.

---

## 🕳️ Pi-hole / FTL

**Problem:** FTL flusht neue DNS-Query-Statistiken standardmäßig jede Minute in die SQLite-WAL-Datei (`pihole-FTL.db-wal`) – unabhängig von der tatsächlichen Query-Last.

**Fix** (Pi-hole v6+, TOML-basierte Config):
```bash
sudo pihole-FTL --config database.DBinterval "900"
sudo systemctl restart pihole-FTL
```

**Warum's wirkt:** Erhöht das Flush-Intervall von 60s auf 900s (15 Min) → Faktor 15 weniger Commits. Trade-off: bis zu 15 Minuten Statistik-Verlust bei einem harten Absturz — für ein Homelab vertretbar.

---

## 📈 Grafana

Grafana war der hartnäckigste Kandidat und brauchte drei Maßnahmen:

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

---

## 🔧 Messmethodik

Alle Zahlen wurden mit `fatrace` erhoben:

```bash
sudo timeout 130 fatrace -f W | grep -c <prozessname>
```

Für belastbare Vorher/Nachher-Vergleiche wurde jeweils ein Fenster gewählt, das mindestens einen vollen Intervall-Zyklus der jeweiligen Komponente abdeckt (z.B. 960s für ein 15-Minuten-Flush-Intervall).

---

## ⚠️ Hinweise & Trade-offs

- Alle Änderungen reduzieren die **Persistenz-Frequenz**, nicht die Funktionalität. Im Falle eines Absturzes/Stromausfalls geht der jeweils letzte Intervall an Statistikdaten verloren (Sekunden bis Minuten, keine strukturellen Daten).
- Die Grafana-Token-Rotation von 10 auf 60 Minuten zu strecken erhöht das Zeitfenster für einen gestohlenen Session-Token — nur empfehlenswert für Instanzen, die **nicht** öffentlich im Internet erreichbar sind.
- Vor jeder Config-Änderung: **Backup der Original-Config!**
  ```bash
  sudo cp <config-datei> <config-datei>.bak-$(date +%Y%m%d-%H%M%S)
  ```

---

## 🖥️ Umgebung

- Raspberry Pi (Debian 13 / Trixie)
- Pi-hole v6.4.3 / FTL v6.7
- Grafana v13.2.2
- InfluxDB (1.x)
- ioBroker

---

## 📝 Lizenz

MIT — nutz es, wie du magst. 🎉
