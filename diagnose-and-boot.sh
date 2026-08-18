#!/usr/bin/env bash
# ------------------------------------------------------------------
# Robust EFI diagnosis – uses losetup --show, detaches stale loops.
# All logs go to your repo directory.
# ------------------------------------------------------------------

set -x
REPO_DIR="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo"
LOGFILE="$REPO_DIR/diagnose_boot_fixed_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
echo "=== Starting diagnosis at $(date) ==="
echo "Logging to: $LOGFILE"

# ------------------------------------------------------------------
# 1. Kill stale QEMU processes
# ------------------------------------------------------------------
pkill -f "qemu-system-x86_64.*$IMG" 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Detach any existing loop devices for this image
# ------------------------------------------------------------------
sudo losetup -l | grep "$IMG" | awk '{print $1}' | while read dev; do
    echo "Detaching stale loop: $dev"
    sudo losetup -d "$dev" 2>/dev/null || true
done

# ------------------------------------------------------------------
# 3. Verify image and OVMF
# ------------------------------------------------------------------
if [ ! -f "$IMG" ]; then
    echo "ERROR: Image not found."
    exit 1
fi

if [ ! -f /usr/share/OVMF/OVMF_CODE.fd ] && [ ! -f /usr/share/edk2-ovmf/x64/OVMF_CODE.fd ]; then
    echo "ERROR: OVMF not installed. Install with: sudo dnf install edk2-ovmf"
    exit 1
fi

# ------------------------------------------------------------------
# 4. Mount EFI partition using losetup --show (single device)
# ------------------------------------------------------------------
echo "Setting up loop device..."
LOOP_DEV=$(sudo losetup -f -P --show "$IMG")
if [ -z "$LOOP_DEV" ]; then
    echo "ERROR: Failed to set up loop device."
    exit 1
fi
echo "Loop device: $LOOP_DEV"

# Find EFI partition – usually p1, but let's scan all partitions for type EFI
EFI_PART=""
for part in "${LOOP_DEV}"p*; do
    if [ -b "$part" ]; then
        # Check if this partition is EFI system partition (type 0xEF or GPT GUID C12A7328-F81F-11D2-BA4B-00A0C93EC93B)
        TYPE=$(sudo fdisk -l "$LOOP_DEV" 2>/dev/null | grep "$part" | awk '{print $6}')
        if [[ "$TYPE" == "EFI" ]] || [[ "$TYPE" == "EFI System" ]]; then
            EFI_PART="$part"
            break
        fi
    fi
done

if [ -z "$EFI_PART" ]; then
    echo "ERROR: Could not find EFI partition on $LOOP_DEV."
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi
echo "EFI partition found: $EFI_PART"

TMP_MOUNT=$(mktemp -d)
sudo mount "$EFI_PART" "$TMP_MOUNT"
echo "EFI partition mounted at $TMP_MOUNT"

# Check for standard bootloader
BOOTLOADER=$(find "$TMP_MOUNT" -name "BOOTX64.EFI" -o -name "grubx64.efi" -o -name "systemd-bootx64.efi" 2>/dev/null | head -n1)
if [ -n "$BOOTLOADER" ]; then
    echo "✅ Found bootloader: $BOOTLOADER"
else
    echo "❌ No bootloader found in EFI partition."
    echo "Contents of $TMP_MOUNT/EFI/BOOT/ :"
    ls -la "$TMP_MOUNT"/EFI/BOOT/ 2>/dev/null || echo "Directory does not exist."
    echo "Contents of $TMP_MOUNT/EFI/ :"
    ls -la "$TMP_MOUNT"/EFI/ 2>/dev/null || echo "Directory does not exist."
fi

sudo umount "$TMP_MOUNT"
rmdir "$TMP_MOUNT"
sudo losetup -d "$LOOP_DEV"

# ------------------------------------------------------------------
# 5. If bootloader exists, try UEFI boot again (with extra options)
# ------------------------------------------------------------------
if [ -n "$BOOTLOADER" ]; then
    echo "Launching QEMU with UEFI and verbose logging (press Ctrl+C to stop)..."
    qemu-system-x86_64 \
        -machine pc,accel=kvm \
        -cpu host \
        -m 4G \
        -drive file="$IMG",if=virtio,format=raw \
        -boot order=c,menu=on \
        -vnc :0 \
        -serial stdio \
        -vga std \
        -bios /usr/share/OVMF/OVMF_CODE.fd \
        -trace events=/tmp/qemu_trace_events.txt 2>&1 | tee /tmp/qemu_verbose.log
    exit $?
fi

# ------------------------------------------------------------------
# 6. No bootloader → propose fallback methods
# ------------------------------------------------------------------
echo
echo "============================================================"
echo "❌ No bootloader found. Your image is likely broken or not"
echo "   meant to be booted directly as a UEFI disk."
echo "============================================================"
echo
echo "Option A: Rebuild the image using 'pmbootstrap'."
echo "   (Recommended: the official way to create a working installer.)"
echo
echo "Option B: Try kernel/initrd boot with root=/dev/vda2."
echo "   (Bypasses the bootloader entirely.)"
echo
echo "To try Option B, run this command in a new terminal:"
echo
echo "qemu-system-x86_64 \\"
echo "  -machine pc,accel=kvm \\"
echo "  -cpu host \\"
echo "  -m 4G \\"
echo "  -drive file=\"$IMG\",if=virtio,format=raw \\"
echo "  -kernel /home/owner/Downloads/vmlinuz-pmos \\"
echo "  -initrd /home/owner/Downloads/initramfs-pmos \\"
echo "  -append 'root=/dev/vda2 console=ttyS0' \\"
echo "  -vnc :0 \\"
echo "  -serial stdio"
echo
echo "If that also fails, you likely need a new image."
echo
echo "Diagnosis complete. Logs saved to $LOGFILE"
