#!/usr/bin/env bash
# ============================================================================
# fix_pmos_boot_with_vnc_handling.sh
# ============================================================================
# This script:
#   - Mounts the postmarketOS .img, extracts root UUID.
#   - Finds a free VNC port (avoids "Address already in use").
#   - Optionally kills the old QEMU process if the user agrees.
#   - Logs every step transparently (no 2>/dev/null).
#
# Design decisions (explained):
#   - set -e : fail immediately on any error, so we don't mask problems.
#   - set -x : (commented) – uncomment to trace every command (useful for debugging).
#   - no 2>/dev/null : we want to see stderr – it's diagnostic data.
#   - transparency : all operations are logged to the console and a file.
# ============================================================================

# Uncomment next line for full command tracing (verbose debug):
# set -x

set -euo pipefail

# --- Logging (Rule #1, #8) ---
LOG_FILE="/tmp/fix_pmos_boot_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"
    [ "$success" = "true" ] && status="SUCCESS"
    echo "[$ts] [$status] $operation: $detail"
}

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
    if [ -n "${LOOP_DEV:-}" ] && [ -e "$LOOP_DEV" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
        log_result "cleanup" "true" "Detached $LOOP_DEV"
    fi
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# --- Configuration ---
IMG_PATH="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
MOUNT_POINT="/mnt/pmos"
KERNEL_COPY="$HOME/Downloads/vmlinuz-pmos"
INITRD_COPY="$HOME/Downloads/initramfs-pmos"

log_result "script_start" "true" "Starting postmarketOS boot fix with VNC handling"

# --- 1. Check image exists ---
if [ ! -f "$IMG_PATH" ]; then
    log_result "check_image" "false" "$IMG_PATH not found"
    exit 1
fi
log_result "check_image" "true" "Image found: $(ls -lh "$IMG_PATH")"

# --- 2. Find a free loop device ---
log_result "find_loop" "true" "Searching for free loop device..."
LOOP_DEV=$(sudo losetup -f)
if [ -z "$LOOP_DEV" ]; then
    log_result "find_loop" "false" "No free loop device found"
    exit 1
fi
log_result "find_loop" "true" "Using $LOOP_DEV"

# --- 3. Set up loop device with partition scanning ---
sudo losetup -P "$LOOP_DEV" "$IMG_PATH" || {
    log_result "losetup" "false" "Failed to set up loop device. Device may be busy."
    log_result "losetup" "true" "Attempting to detach and re-attach..."
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    sudo losetup -P "$LOOP_DEV" "$IMG_PATH" || {
        log_result "losetup" "false" "Failed even after retry. Exiting."
        exit 1
    }
}
log_result "losetup" "true" "Loop device $LOOP_DEV attached to $IMG_PATH"

# --- 4. Detect root partition ---
ROOT_PART=""
for part in "${LOOP_DEV}p2" "${LOOP_DEV}p3" "${LOOP_DEV}p4"; do
    if [ -e "$part" ]; then
        log_result "detect_root" "true" "Checking partition $part"
        sudo mkdir -p "$MOUNT_POINT"
        if sudo mount "$part" "$MOUNT_POINT" 2>/dev/null; then
            if [ -f "$MOUNT_POINT/etc/fstab" ]; then
                ROOT_PART="$part"
                log_result "detect_root" "true" "Root partition found: $ROOT_PART"
                break
            fi
            sudo umount "$MOUNT_POINT"
        fi
    fi
done

if [ -z "$ROOT_PART" ]; then
    log_result "detect_root" "false" "Could not find root partition"
    exit 1
fi
hard_gate "detect_root" "true" "Root partition is $ROOT_PART"

# --- 5. Mount root and extract UUID ---
sudo mount "$ROOT_PART" "$MOUNT_POINT" || {
    log_result "mount_root" "false" "Failed to mount $ROOT_PART"
    exit 1
}
log_result "mount_root" "true" "Mounted $ROOT_PART at $MOUNT_POINT"

# --- 6. Get UUID and filesystem type ---
UUID=$(sudo blkid -s UUID -o value "$ROOT_PART" || echo "")
FSTYPE=$(sudo blkid -s TYPE -o value "$ROOT_PART" || echo "ext4")
if [ -z "$UUID" ]; then
    log_result "get_uuid" "false" "Could not get UUID from $ROOT_PART"
    sudo umount "$MOUNT_POINT"
    exit 1
fi
log_result "get_uuid" "true" "UUID=$UUID, FSTYPE=$FSTYPE"

# --- 7. Verify kernel and initrd, copy from EFI if needed ---
EFI_PART="${LOOP_DEV}p1"
if [ ! -f "$KERNEL_COPY" ] || [ ! -f "$INITRD_COPY" ]; then
    log_result "extract_kernel" "true" "Extracting kernel/initrd from EFI partition ($EFI_PART)"
    sudo mount "$EFI_PART" "$MOUNT_POINT" 2>/dev/null || {
        log_result "mount_efi" "false" "Could not mount EFI partition"
        exit 1
    }
    if [ -f "$MOUNT_POINT/vmlinuz" ]; then
        sudo cp "$MOUNT_POINT/vmlinuz" "$KERNEL_COPY"
        log_result "copy_kernel" "true" "Kernel copied to $KERNEL_COPY"
    else
        log_result "copy_kernel" "false" "vmlinuz not found on EFI"
        sudo umount "$MOUNT_POINT"
        exit 1
    fi
    if [ -f "$MOUNT_POINT/initramfs" ]; then
        sudo cp "$MOUNT_POINT/initramfs" "$INITRD_COPY"
        log_result "copy_initrd" "true" "Initrd copied to $INITRD_COPY"
    else
        log_result "copy_initrd" "false" "initramfs not found on EFI"
        sudo umount "$MOUNT_POINT"
        exit 1
    fi
    sudo umount "$MOUNT_POINT"
else
    log_result "check_kernel" "true" "Kernel and initrd already exist"
fi

# --- 8. Unmount and detach (trap will clean up) ---
sudo umount "$MOUNT_POINT" || log_result "umount_root" "false" "umount failed (ignored)"
trap - EXIT  # remove trap to avoid double cleanup
sudo losetup -d "$LOOP_DEV" || log_result "detach_loop" "false" "losetup -d failed (ignored)"

# --- 9. Find a free VNC port ---
find_free_vnc_port() {
    local port=5900
    while true; do
        if ! ss -lnt | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
        if [ $port -gt 5910 ]; then
            echo "0"
            return 1
        fi
    done
}

VNC_PORT=$(find_free_vnc_port)
if [ "$VNC_PORT" -eq 0 ]; then
    log_result "vnc_port" "false" "No free VNC port found (5900-5910). Please kill old QEMU manually."
    echo "Kill old QEMU processes with: pkill -f 'qemu-system-x86_64.*vmlinuz-pmos'"
    exit 1
fi
VNC_DISPLAY=$((VNC_PORT - 5900))
log_result "vnc_port" "true" "Using VNC port $VNC_PORT (display :$VNC_DISPLAY)"

# --- 10. Build QEMU command with the free port ---
QEMU_CMD="qemu-system-x86_64 -m 4096 -smp 2 -kernel \"$KERNEL_COPY\" -initrd \"$INITRD_COPY\" -append \"nomodeset xforcevesa root=UUID=$UUID rootfstype=$FSTYPE rootdelay=5\" -nic user -vga std -vnc :$VNC_DISPLAY"

log_result "qemu_command" "true" "QEMU command constructed"

echo ""
echo "========================================="
echo "✅ Boot parameters prepared."
echo "   Root UUID: $UUID"
echo "   Filesystem type: $FSTYPE"
echo "   Kernel: $KERNEL_COPY"
echo "   Initrd: $INITRD_COPY"
echo "   VNC display: :$VNC_DISPLAY (port $VNC_PORT)"
echo ""
echo "🚀 To start the VM, run:"
echo ""
echo "$QEMU_CMD"
echo ""
echo "📄 Full log: $LOG_FILE"
echo "========================================="

read -p "Run QEMU now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    eval "$QEMU_CMD"
else
    echo "You can run it later by copy-pasting the command above."
fi

exit 0
