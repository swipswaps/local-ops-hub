#!/usr/bin/env bash
IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"

echo "🔄 Killing stale QEMU..."
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Launching VM in background..."
qemu-system-x86_64 \
  -machine pc,accel=kvm -cpu host -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -kernel "$KERNEL" -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0" \
  -vnc :0 -serial stdio -vga std &

QEMU_PID=$!
echo "QEMU started with PID $QEMU_PID. Waiting 10 seconds for boot..."
sleep 10

echo "✅ Launching VNC Viewer..."
vncviewer localhost:5900

# If you kill VNC, bring the VM back to the foreground or kill it
echo "VM is still running (PID $QEMU_PID). Press Ctrl+C in this terminal to kill the VM."
wait $QEMU_PID
