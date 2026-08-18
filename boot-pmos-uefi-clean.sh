#!/usr/bin/env bash
IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Booting postmarketOS with UEFI (no trace) ..."
qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -boot order=c,menu=on \
  -vnc :0 \
  -serial stdio \
  -vga std \
  -bios /usr/share/OVMF/OVMF_CODE.fd
