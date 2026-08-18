#!/usr/bin/env bash
# ------------------------------------------------------------------
# Direct kernel+initrd boot with root=/dev/vda2 (bypasses UEFI)
# All logs go to your repo directory.
# ------------------------------------------------------------------

set -x
REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/kernel_direct_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"

echo "=== Starting direct kernel boot at $(date) ==="
echo "Logging to: $LOGFILE"

# Verify required files
if [ ! -f "$IMG" ] || [ ! -f "$KERNEL" ] || [ ! -f "$INITRD" ]; then
    echo "ERROR: Missing image, kernel, or initrd. Ensure vmlinuz-pmos and initramfs-pmos exist in ~/Downloads/"
    exit 1
fi

# Kill any stale QEMU processes
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

echo "🚀 Booting kernel+initrd with root=/dev/vda2 ..."
qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0" \
  -vnc :0 \
  -serial stdio \
  -vga std

QEMU_EXIT=$?
echo "=== QEMU exited with status $QEMU_EXIT at $(date) ==="
