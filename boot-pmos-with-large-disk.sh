#!/usr/bin/env bash
# ------------------------------------------------------------------
# Boot the installer with an additional 8 GB disk for installation.
# All logs go to the repo directory.
# ------------------------------------------------------------------

set -x  # verbose debugging

REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/boot_large_disk_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"
NEWDISK="$REPO_DIR/pmos-install-disk.qcow2"

echo "=== Starting boot with large disk at $(date) ==="
echo "Logging to: $LOGFILE"

# ------------------------------------------------------------------
# 1. Kill stale QEMU processes
# ------------------------------------------------------------------
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Verify required files exist (gate asserts)
# ------------------------------------------------------------------
if [ ! -f "$IMG" ]; then
    echo "ERROR: Installer image not found: $IMG"
    exit 1
fi
if [ ! -f "$KERNEL" ] || [ ! -f "$INITRD" ]; then
    echo "ERROR: Kernel or initrd missing in ~/Downloads/"
    exit 1
fi
if [ ! -f "$NEWDISK" ]; then
    echo "ERROR: New disk file not found. Did you run 'qemu-img create'?"
    echo "Run: qemu-img create -f qcow2 $NEWDISK 8G"
    exit 1
fi

# ------------------------------------------------------------------
# 3. Display disk sizes for confirmation
# ------------------------------------------------------------------
echo "Installer image: $(ls -lh "$IMG" | awk '{print $5}')"
echo "New disk:        $(ls -lh "$NEWDISK" | awk '{print $5}')"

# ------------------------------------------------------------------
# 4. Boot QEMU with both disks (vda = installer, vdb = target)
# ------------------------------------------------------------------
echo "🚀 Launching QEMU (vda = installer, vdb = target disk)..."
qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -drive file="$NEWDISK",if=virtio,format=qcow2 \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0" \
  -vnc :0 \
  -serial stdio \
  -vga virtio

QEMU_EXIT=$?
echo "=== QEMU exited with status $QEMU_EXIT at $(date) ==="
