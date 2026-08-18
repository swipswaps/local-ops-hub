#!/usr/bin/env bash
IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"
NEWDISK="$REPO_DIR/pmos-install-disk.qcow2"

pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Booting with SPICE (mouse offset fixed)..."
qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -drive file="$NEWDISK",if=virtio,format=qcow2 \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0" \
  -spice port=5900,disable-ticketing=on \
  -serial stdio \
  -vga virtio
