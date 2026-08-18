#!/usr/bin/env bash
# ------------------------------------------------------------------
# Script placed correctly inside the project repo.
# Auto-detects UEFI vs Legacy BIOS and boots accordingly.
# Logs go to /home/owner/Documents/.../repo/pmos_boot_auto_*.log
# ------------------------------------------------------------------

set -x
REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/pmos_boot_auto_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"

echo "=== Starting auto-detection boot at $(date) ==="
echo "Logging to: $LOGFILE"

# Kill stale QEMU processes
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

# Detect partition table type
if [ ! -f "$IMG" ]; then
    echo "ERROR: Image not found at $IMG"
    exit 1
fi

HAS_EFI=$(sudo fdisk -l "$IMG" 2>/dev/null | grep -i "EFI System")
if [ -n "$HAS_EFI" ]; then
    echo ">>> Detected UEFI (GPT) partition. Booting with UEFI firmware."
    BIOS_ARG="-bios /usr/share/OVMF/OVMF_CODE.fd"
    # Fallback OVMF paths if not found
    if [ ! -f "/usr/share/OVMF/OVMF_CODE.fd" ] && [ -f "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" ]; then
        BIOS_ARG="-bios /usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
    elif [ ! -f "/usr/share/OVMF/OVMF_CODE.fd" ] && [ -f "/usr/share/qemu/OVMF.fd" ]; then
        BIOS_ARG="-bios /usr/share/qemu/OVMF.fd"
    else
        echo "WARNING: UEFI detected but OVMF firmware not found. Falling back to legacy BIOS."
        BIOS_ARG=""
    fi
else
    echo ">>> Detected Legacy BIOS (MBR) partition. Booting without UEFI firmware."
    BIOS_ARG=""
fi

echo "Launching QEMU... (press Ctrl+C to stop)"
qemu-system-x86_64 \
    -machine pc,accel=kvm \
    -cpu host \
    -m 4G \
    -drive file="$IMG",if=virtio,format=raw \
    -boot order=c,menu=on \
    -vnc :0 \
    -serial stdio \
    -vga std \
    ${BIOS_ARG}

QEMU_EXIT=$?
echo "=== QEMU exited with status $QEMU_EXIT at $(date) ==="
