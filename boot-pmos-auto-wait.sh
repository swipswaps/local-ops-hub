#!/usr/bin/env bash
IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"

pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Launching VM with live log detection..."
# stdbuf -oL forces line-buffered output so the grep doesn't stall
stdbuf -oL -eL qemu-system-x86_64 \
  -machine pc,accel=kvm -cpu host -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -kernel "$KERNEL" -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0" \
  -vnc :0 -vga std -serial stdio 2>&1 | \
  tee /tmp/pmos_boot_wait.log | \
  grep --line-buffered -m 1 "Reached target Graphical Interface"

echo "✅ Graphical Interface reached. Waiting 10 seconds for framebuffer..."
sleep 10

echo "🚀 Launching VNC viewer..."
vncviewer localhost:5900
