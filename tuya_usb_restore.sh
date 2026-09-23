#!/bin/bash
set -e

USB_TARGET_DIR="/media/usbdrive/iobroker-mirror/opt/iobroker/node_modules/iobroker.js-controller"
PIDS_FILE="/opt/iobroker/node_modules/iobroker.js-controller/pids.txt"

echo "======================================================"
echo "  Tuya pids.txt auf USB auslagern"
echo "======================================================"
echo ""

if [ -L "$PIDS_FILE" ]; then
  echo "Hinweis: $PIDS_FILE ist bereits ein Symlink."
  ls -la "$PIDS_FILE"
  exit 0
fi

if [ ! -f "$PIDS_FILE" ]; then
  echo "Fehler: $PIDS_FILE nicht gefunden."
  exit 1
fi

echo "Bitte deaktiviere jetzt kurz den Tuya-Adapter in der"
echo "ioBroker Admin-Oberfläche (Instanzen -> tuya.0 -> Schalter aus)."
echo ""
read -p "Fertig? Weiter mit [j] / Abbrechen mit [n]: " confirm

if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
  echo "Abgebrochen."
  exit 1
fi

echo ""
OWNER=$(stat -c '%U:%G' "$PIDS_FILE")

echo "-> Lege Zielverzeichnis auf USB an..."
sudo mkdir -p "$USB_TARGET_DIR"

echo "-> Verschiebe pids.txt auf USB..."
sudo mv "$PIDS_FILE" "$USB_TARGET_DIR/pids.txt"

echo "-> Setze Besitzrechte ($OWNER)..."
sudo chown "$OWNER" "$USB_TARGET_DIR/pids.txt"

echo "-> Erstelle Symlink..."
sudo ln -s "$USB_TARGET_DIR/pids.txt" "$PIDS_FILE"

echo ""
echo "-> Fertig! Verifizierung:"
ls -la "$PIDS_FILE"

echo ""
echo "Du kannst den Tuya-Adapter jetzt wieder aktivieren."
