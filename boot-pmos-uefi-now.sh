#!/usr/bin/env bash
# ------------------------------------------------------------------
# One‑shot script: install OVMF, kill stale QEMU, boot with UEFI.
# Logs everything to your repo directory.
# ------------------------------------------------------------------

set -x
REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/pmos_uefi_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"

echo "=== Starting UEFI boot preparation at $(date) ==="
echo "Logging to: $LOGFILE"

# ------------------------------------------------------------------
# 1. Kill any existing QEMU using this image
# ------------------------------------------------------------------
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Ensure OVMF UEFI firmware is installed
# ------------------------------------------------------------------
OVMF_PATHS=(
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
    "/usr/share/qemu/OVMF.fd"
)
BIOS_ARG=""
for path in "${OVMF_PATHS[@]}"; do
    if [ -f "$path" ]; then
        BIOS_ARG="-bios $path"
        echo "Found OVMF at: $path"
        break
    fi
done

if [ -z "$BIOS_ARG" ]; then
    echo "OVMF not found. Installing edk2-ovmf (Fedora)..."
    sudo dnf install -y edk2-ovmf
    # Re-check after installation
    for path in "${OVMF_PATHS[@]}"; do
        if [ -f "$path" ]; then
            BIOS_ARG="-bios $path"
            echo "OVMF installed at: $path"
            break
        fi
    done
    if [ -z "$BIOS_ARG" ]; then
        echo "ERROR: OVMF still not found after installation. Please check manually."
        exit 1
    fi
else
    echo "OVMF already present, skipping installation."
fi

# ------------------------------------------------------------------
# 3. Launch QEMU with UEFI and proper graphics
# ------------------------------------------------------------------
echo "Launching QEMU with UEFI (press Ctrl+C to stop)..."
qemu-system-x86_64 \
    -machine pc,accel=kvm \
    -cpu host \
    -m 4G \
    -drive file="$IMG",if=virtio,format=raw \
    -boot order=c,menu=on \
    -vnc :0 \
    -serial stdio \
    -vga std \
    $BIOS_ARG

QEMU_EXIT=$?
echo "=== QEMU exited with status $QEMU_EXIT at $(date) ==="
