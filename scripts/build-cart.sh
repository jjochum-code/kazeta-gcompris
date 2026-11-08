#!/bin/bash
# Baut eine Kazeta-Cartridge mit GCompris in ein Verzeichnis
# (z. B. die eingehängte ext4-Partition eines USB-Sticks oder einer SD-Karte).
#
#   ./build-cart.sh /run/media/$USER/gcompris
#
# Lädt GCompris (Linux 64 Bit) und die Kazeta-Linux-Runtime herunter,
# prüft Signatur bzw. Prüfsumme und legt cart.kzi + icon.png daneben.
set -euo pipefail

GCOMPRIS_VERSION=26.2
GCOMPRIS_URL="https://download.kde.org/stable/gcompris/qt/linux/gcompris-qt-${GCOMPRIS_VERSION}-Linux64.sh"
GCOMPRIS_KEY=D2FAAB621F618D42685B427B63D7264C05687D7E   # Timothée Giet (GCompris-Maintainer)
RUNTIME_URL="https://runtimes.kazeta.org/linux-1.0.kzr"
RUNTIME_SHA256=9edbd30da69a04770b2780f30e86b74d162279f0cfb1650faf383dd86301a1dc

TARGET=${1:?Zielverzeichnis angeben, z. B. /run/media/$USER/gcompris}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo ">> GCompris ${GCOMPRIS_VERSION} herunterladen und Signatur prüfen"
curl -f#L -o "$WORK/gcompris.sh" "$GCOMPRIS_URL"
curl -fsL -o "$WORK/gcompris.sh.sig" "$GCOMPRIS_URL.sig"
export GNUPGHOME="$WORK/gnupg"; mkdir -m 700 "$GNUPGHOME"
gpg -q --keyserver hkps://keyserver.ubuntu.com --recv-keys "$GCOMPRIS_KEY"
gpg -q --verify "$WORK/gcompris.sh.sig" "$WORK/gcompris.sh"

echo ">> Kazeta-Linux-Runtime herunterladen und Prüfsumme prüfen"
curl -f#L -o "$WORK/linux-1.0.kzr" "$RUNTIME_URL"
echo "$RUNTIME_SHA256  $WORK/linux-1.0.kzr" | sha256sum -c -

echo ">> GCompris nach $TARGET/content entpacken (ohne das Installer-Skript auszuführen)"
# Das .sh ist ein CPack-Archiv: Shell-Kopf, danach ein tar.gz ab der Zeile, die der Kopf mit "tail +N" nennt
line=$(grep -a -m1 -oE 'tail \$use_new_tail_syntax \+[0-9]+ "\$0" \| gunzip' "$WORK/gcompris.sh" | grep -oE '\+[0-9]+' | tr -d +)
[ -n "$line" ] || { echo "Archiv-Start im GCompris-Installer nicht gefunden"; exit 1; }
mkdir -p "$TARGET/content"
tail -n +"$line" "$WORK/gcompris.sh" | gunzip | tar -x -C "$TARGET/content"

cp "$WORK/linux-1.0.kzr" "$TARGET/"
cp "$HERE/cart/cart.kzi" "$HERE/cart/icon.png" "$TARGET/"
chmod -R a+rX "$TARGET"
echo ">> Fertig:"; ls -la "$TARGET"
