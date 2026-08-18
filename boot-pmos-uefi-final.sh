#!/usr/bin/env bash
# ------------------------------------------------------------------
# UEFI boot with bootindex=0 and boot menu – no manual intervention.
# Logs go to /home/owner/Documents/.../repo/boot_final.log
# ------------------------------------------------------------------

set -x
REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/boot_final_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"

echo "=== Starting UEFI boot at $(date) ==="
echo "Logging to: $LOGFILE"

# Kill any leftover QEMU processes using this image
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

# Verify OVMF exists
if [ ! -f /usr/share/OVMF/OVMF_CODE.fd ] && [ ! -f /usr/share/edk2-ovmf/x64/OVMF_CODE.fd ]; then
    echo "ERROR: OVMF not installed. Run: sudo dnf install edk2-ovmf"
    exit 1
fi

# Launch QEMU with explicit bootindex=0 and boot menu
echo "🚀 Launching QEMU with UEFI (bootindex=0, menu=on)..."
qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=none,id=drive0,format=raw \
  -device virtio-blk-pci,drive=drive0,bootindex=0 \
  -boot menu=on \
  -vnc :0 \
  -serial stdio \
  -vga std \
  -bios /usr/share/OVMF/OVMF_CODE.fd

QEMU_EXIT=$?
echo "=== QEMU exited with status $QEMU_EXIT at $(date) ==="
