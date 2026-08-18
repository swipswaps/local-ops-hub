#!/usr/bin/env bash
IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"

pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Booting with forced VESA graphics mode..."
echo "✅ Watch serial console for 'generic-x86-64 login:'."
echo "✅ Then wait 15 seconds for the VNC window to switch to the GUI."

qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0 nomodeset video=1024x768" \
  -vnc :0 \
  -serial stdio \
  -vga std
