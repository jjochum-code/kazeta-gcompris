#!/bin/bash
# Baut aus einem fertigen Kazeta+GCompris-Stick ein kompaktes 29-GiB-Image. Der Stick wird nur gelesen.
#
#   sudo ./make-image.sh /dev/sdX /pfad/zur/cart ./ausgabe
#
# Erwartet auf dem Stick: 1 frzr_efi, 2 frzr_root (btrfs), 3 gcompris (ext4).
# Im Image werden Spielstände, Logs und Zufalls-Seed entfernt.
set -euo pipefail

CART=${2:?Cartridge-Verzeichnis angeben}
OUT=${3:-.}; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
IMG="$OUT/kazeta-gcompris.img"
TMP2="$OUT/root-tmp.btrfs"

P2_SECTORS=50331648   # 24 GiB
P3_SECTORS=8388608    # 4 GiB

[ "$(id -u)" = 0 ] || { echo "Bitte als root starten"; exit 1; }
DEV=$(readlink -f "${1:?Stick-Gerät angeben, z. B. /dev/sdb}")
[ "$(blkid -s LABEL -o value ${DEV}1)" = frzr_efi ] && [ "$(blkid -s LABEL -o value ${DEV}2)" = frzr_root ] \
  && [ "$(blkid -s LABEL -o value ${DEV}3)" = gcompris ] || { echo "Unerwartete Aufteilung, Abbruch"; exit 1; }
for p in $(lsblk -nlo PATH "$DEV"); do umount "$p" 2>/dev/null || true; done
MNT=$(mktemp -d); LOOPS=()
cleanup() { umount "$MNT" 2>/dev/null || true; for l in "${LOOPS[@]}"; do losetup -d "$l" 2>/dev/null || true; done; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

P1_START=$(cat /sys/block/${DEV#/dev/}/${DEV#/dev/}1/start); P1_SIZE=$(cat /sys/block/${DEV#/dev/}/${DEV#/dev/}1/size)
P2_START=$(cat /sys/block/${DEV#/dev/}/${DEV#/dev/}2/start)
P3_START=$((P2_START + P2_SECTORS))
TOTAL=$((P3_START + P3_SECTORS + 2048))

echo ">> 1/7 Partitionstabelle (gleiche IDs wie der Stick) im Image anlegen"
rm -f "$IMG"; truncate -s $((TOTAL * 512)) "$IMG"
sfdisk --dump "$DEV" | grep -vE '^(last-lba|first-lba|device):' \
  | sed -E "s|^${DEV}2 : start= *([0-9]+), size= *[0-9]+|${DEV}2 : start= \1, size= ${P2_SECTORS}|; s|^${DEV}3 : start= *[0-9]+, size= *[0-9]+|${DEV}3 : start= ${P3_START}, size= ${P3_SECTORS}|; s|^${DEV}|IMG|" \
  | tee "$OUT/layout.sfdisk"
sfdisk --wipe never -q "$IMG" < "$OUT/layout.sfdisk"
sfdisk -l "$IMG" | tail -4

echo ">> 2/7 EFI-Partition kopieren"
dd if=${DEV}1 of="$IMG" bs=4M seek=$((P1_START * 512)) oflag=seek_bytes conv=notrunc status=none

echo ">> 3/7 Kazeta-System (64 GiB) zwischenspeichern"
dd if=${DEV}2 of="$TMP2" bs=4M conv=sparse status=progress
btrfs device scan --forget || true
L=$(losetup -f --show "$TMP2"); LOOPS+=("$L")
btrfs device scan --forget || true
mount "$L" "$MNT"
findmnt -no SOURCE "$MNT" | grep -q loop || { echo "Falsches Gerät eingehängt, Abbruch"; exit 1; }

echo ">> 4/7 Spielstände, Logs und Zufalls-Seed entfernen"
find "$MNT" -maxdepth 6 -type d \( -path '*/kazeta/saves' -o -path '*/kazeta/cache' -o -path '*/kazeta/run' \) -print 2>/dev/null | while read -r d; do
  echo "   leere $d:"; ls -A "$d" | sed 's/^/     - /'; find "$d" -mindepth 1 -delete || true
done || true
find "$MNT" -maxdepth 6 \( -path '*/log/journal' -type d \) -print 2>/dev/null | while read -r d; do echo "   leere $d"; find "$d" -mindepth 1 -delete || true; done || true
find "$MNT" -maxdepth 6 \( -name random-seed -path '*/systemd/*' -o -name 'session.log*' \) -print -delete 2>/dev/null || true

echo ">> 5/7 Kazeta-System auf 24 GiB verkleinern und ins Image übernehmen"
btrfs filesystem resize 23G "$MNT"
sync; umount "$MNT"; losetup -d "$L"; LOOPS=()
dd if="$TMP2" of="$IMG" bs=4M count=$((P2_SECTORS * 512 / 4194304)) seek=$((P2_START * 512)) oflag=seek_bytes conv=notrunc,sparse status=progress
rm -f "$TMP2"
btrfs device scan --forget || true
L=$(losetup -fP --show "$IMG"); LOOPS+=("$L")
udevadm settle
btrfs device scan --forget || true
mount "${L}p2" "$MNT"
findmnt -no SOURCE "$MNT" | grep -q "${L}p2" || { echo "Falsches Gerät eingehängt, Abbruch"; exit 1; }
btrfs filesystem resize max "$MNT"
fstrim -v "$MNT" || true
sync; umount "$MNT"
btrfs check --readonly "${L}p2"

echo ">> 6/7 GCompris-Cartridge (4 GiB, ext4 'gcompris')"
mkfs.ext4 -q -F -L gcompris "${L}p3"
mount "${L}p3" "$MNT"
cp -a "$CART"/. "$MNT"/; rm -rf "$MNT/lost+found"
chown -R root:root "$MNT"; chmod -R a+rX "$MNT"
fstrim -v "$MNT" || true
sync; umount "$MNT"
fsck.ext4 -fn "${L}p3" | tail -1
fsck.vfat -n "${L}p1" | tail -1

echo ">> 7/7 Ergebnis"
mount -o ro "${L}p1" "$MNT"; echo "   Bootloader-Einträge:"; find "$MNT" -name '*.conf' -path '*entries*' -exec sh -c 'echo "   $1"; sed "s/^/     /" "$1"' _ {} \; ; umount "$MNT"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$L"
losetup -d "$L"; LOOPS=()
U=${SUDO_UID:-${PKEXEC_UID:-1000}}; chown "$U:$(id -g "$U")""$IMG" "$OUT/layout.sfdisk"
ls -lsh "$IMG"
echo ">> Fertig."
