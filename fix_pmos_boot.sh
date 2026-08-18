#!/usr/bin/env bash
# ============================================================================
# fix_pmos_boot.sh – Automatically repair postmarketOS boot in QEMU
# Uses the root partition UUID from the image for reliable boot.
# Logs every step to /tmp/fix_pmos_boot.log
# ============================================================================

set -euo pipefail

# --- Logging helper (Rule #1, #8) ---
LOG_FILE="/tmp/fix_pmos_boot.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local status="FAILURE"
    [ "$success" = "true" ] && status="SUCCESS"
    echo "[$ts] [$status] $operation: $detail"
}

# --- Hard gate (Rule #30) ---
hard_gate() {
    local task="$1"
    local ok="$2"
    local detail="$3"
    if [ "$ok" != "true" ]; then
        log_result "hard_gate" "false" "BLOCKED: $task – $detail"
        exit 1
    fi
    log_result "hard_gate" "true" "$task succeeded"
}

# --- Cleanup ---
cleanup() {
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# --- Configuration ---
IMG_PATH="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
MOUNT_POINT="/mnt/pmos"
KERNEL_COPY="$HOME/Downloads/vmlinuz-pmos"
INITRD_COPY="$HOME/Downloads/initramfs-pmos"

log_result "script_start" "true" "Starting postmarketOS boot fix"

# --- 1. Check image exists ---
if [ ! -f "$IMG_PATH" ]; then
    log_result "check_image" "false" "$IMG_PATH not found"
    exit 1
fi
log_result "check_image" "true" "Image found"

# --- 2. Mount image partitions ---
log_result "mount_image" "true" "Setting up loop device for $IMG_PATH"
sudo losetup -P /dev/loop0 "$IMG_PATH"
LOOP_DEV="/dev/loop0"

# Detect root partition (usually p2, but we verify with fdisk)
ROOT_PART=""
for part in "${LOOP_DEV}p2" "${LOOP_DEV}p3"; do
    if [ -e "$part" ]; then
        # Check if it contains /etc/fstab by mounting and testing
        sudo mount "$part" "$MOUNT_POINT" 2>/dev/null && {
            if [ -f "$MOUNT_POINT/etc/fstab" ]; then
                ROOT_PART="$part"
                log_result "detect_root" "true" "Root partition found: $ROOT_PART"
                break
            fi
            sudo umount "$MOUNT_POINT"
        }
    fi
done
hard_gate "detect_root" "$ROOT_PART" "Root partition not found"

# --- 3. Extract UUID and filesystem type ---
sudo mount "$ROOT_PART" "$MOUNT_POINT"
log_result "mount_root" "true" "Mounted $ROOT_PART at $MOUNT_POINT"

UUID=$(sudo blkid -s UUID -o value "$ROOT_PART" || echo "")
FSTYPE=$(sudo blkid -s TYPE -o value "$ROOT_PART" || echo "ext4")
if [ -z "$UUID" ]; then
    log_result "get_uuid" "false" "Could not get UUID from $ROOT_PART"
    exit 1
fi
log_result "get_uuid" "true" "UUID=$UUID, FSTYPE=$FSTYPE"

# --- 4. Verify kernel and initrd exist (copy from EFI partition if needed) ---
EFI_PART="${LOOP_DEV}p1"
if [ ! -f "$KERNEL_COPY" ] || [ ! -f "$INITRD_COPY" ]; then
    log_result "extract_kernel" "true" "Extracting kernel/initrd from EFI partition"
    sudo mount "$EFI_PART" "$MOUNT_POINT" 2>/dev/null || {
        log_result "mount_efi" "false" "Could not mount EFI partition"
        exit 1
    }
    sudo cp "$MOUNT_POINT/vmlinuz" "$KERNEL_COPY" 2>/dev/null || {
        log_result "copy_kernel" "false" "vmlinuz not found on EFI"
        sudo umount "$MOUNT_POINT"
        exit 1
    }
    sudo cp "$MOUNT_POINT/initramfs" "$INITRD_COPY" 2>/dev/null || {
        log_result "copy_initrd" "false" "initramfs not found on EFI"
        sudo umount "$MOUNT_POINT"
        exit 1
    }
    sudo umount "$MOUNT_POINT"
    log_result "extract_kernel" "true" "Kernel and initrd copied"
fi

# --- 5. Unmount and detach loop ---
sudo umount "$MOUNT_POINT" || log_result "umount_root" "false" "umount failed (ignored)"
sudo losetup -d "$LOOP_DEV" || log_result "detach_loop" "false" "losetup -d failed (ignored)"
trap - EXIT  # remove trap to avoid double cleanup

# --- 6. Build QEMU command ---
QEMU_CMD="qemu-system-x86_64 -m 4096 -smp 2 -kernel \"$KERNEL_COPY\" -initrd \"$INITRD_COPY\" -append \"nomodeset xforcevesa root=UUID=$UUID rootfstype=$FSTYPE rootdelay=5\" -nic user -vga std -vnc :0"

log_result "qemu_command" "true" "QEMU command constructed"

echo ""
echo "========================================="
echo "✅ Boot parameters prepared."
echo "   Root UUID: $UUID"
echo "   Filesystem type: $FSTYPE"
echo ""
echo "🚀 To start the VM, run:"
echo ""
echo "$QEMU_CMD"
echo ""
echo "📄 Log saved to: $LOG_FILE"
echo "========================================="

# Optionally, ask user if they want to execute it now
read -p "Run QEMU now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    eval "$QEMU_CMD"
else
    echo "You can run it later by copy-pasting the command above."
fi

exit 0
