# 🔄 tuya_usb_restore.sh

Kleines Helfer-Skript, um die `pids.txt` des ioBroker `js-controller` per Symlink auf die USB-Festplatte auszulagern – Hintergrund und Motivation dazu stehen in der Haupt-README unter [🏠 ioBroker](./README.md#-iobroker).

## Wann man das braucht

Manche Adapter (bei uns: Tuya, wenn kein Zielgerät erreichbar ist) geraten in einen Reconnect-Loop und starten sich minütlich neu. Jeder Start/Stopp lässt den `js-controller` `pids.txt` neu schreiben – bei einem hartnäckigen Loop kann das zu einer überraschend hohen SD-Karten-Last führen, unabhängig von allen anderen Optimierungen. Statt die Ursache im Adapter selbst zu jagen, verschiebt dieses Skript einfach die Datei aus der Schusslinie: per Symlink auf die USB-Platte, mit gespiegelter Verzeichnisstruktur.

## Verwendung

```bash
./tuya_usb_restore.sh
```

Das Skript führt dich durch den Vorgang:

1. Prüft, ob `pids.txt` schon ein Symlink ist (dann bricht es sofort ab – kein Doppelt-Ausführen möglich)
2. Bittet dich, den Tuya-Adapter kurz in der ioBroker Admin-Oberfläche zu deaktivieren, und wartet auf Bestätigung (**j** zum Fortfahren, alles andere bricht ab)
3. Verschiebt `pids.txt` nach `/media/usbdrive/iobroker-mirror/...` (gleiche Pfadstruktur wie auf der SD-Karte, zur besseren Nachvollziehbarkeit)
4. Setzt die ursprünglichen Besitzrechte auf die verschobene Datei
5. Legt an der alten Stelle einen Symlink zur neuen Datei an
6. Zeigt zur Kontrolle das Ergebnis mit `ls -la`

Nach dem Durchlauf einfach den Tuya-Adapter wieder aktivieren.

## Sicherheits-Mechanismen

- **Kein Datenverlust möglich:** Die Originaldatei wird verschoben (nicht kopiert+gelöscht in getrennten Schritten), und das Skript bricht vor jeder riskanten Aktion ab, wenn eine Vorbedingung nicht stimmt (Datei fehlt, ist schon Symlink, keine Bestätigung).
- **`set -e`:** Das Skript stoppt sofort bei jedem unerwarteten Fehler, statt mit halb fertigem Zustand weiterzulaufen.

## Voraussetzung

Das USB-Laufwerk muss unter `/media/usbdrive` eingehängt sein, **bevor** ioBroker startet – sonst zeigt der Symlink beim Booten kurzzeitig ins Leere. Absicherung über systemd:

```bash
sudo systemctl edit iobroker
```
```ini
[Unit]
RequiresMountsFor=/media/usbdrive
After=media-usbdrive.mount
```
```bash
sudo systemctl daemon-reload
```

## Verifizieren, dass es wirkt

```bash
sudo timeout 300 fatrace -f W | grep pids.txt
```
Alle Treffer sollten jetzt auf `/media/usbdrive/...` zeigen, keiner mehr auf der SD-Karte.
