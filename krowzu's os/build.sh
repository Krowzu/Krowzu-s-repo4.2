#!/bin/sh
# Construit nullcore.img (disquette 1.44 Mo amorçable)
#   ./build.sh        -> clavier AZERTY (défaut)
#   ./build.sh us     -> clavier QWERTY
# Dans les deux cas, loadkeys fr / loadkeys us bascule à chaud.
set -e
cd "$(dirname "$0")"

KOPT=""
[ "$1" = "us" ] && KOPT="-DQWERTY"

# logo.inc est régénérable avec : python3 genlogo.py
nasm -f bin bootloader.asm -o boot.bin
nasm -f bin $KOPT kernel.asm -o kernel.bin

# 1.44 Mo = 2880 secteurs de 512 octets
dd if=/dev/zero of=nullcore.img bs=512 count=2880 status=none
dd if=boot.bin   of=nullcore.img conv=notrunc status=none
dd if=kernel.bin of=nullcore.img bs=512 seek=1 conv=notrunc status=none

echo "boot.bin   : $(stat -c%s boot.bin) octets"
echo "kernel.bin : $(stat -c%s kernel.bin) octets"
echo "nullcore.img prêt."
echo
echo "Lancer :  qemu-system-x86_64 -drive file=nullcore.img,format=raw,if=floppy \\"
echo "                             -display gtk,zoom-to-fit=off"
