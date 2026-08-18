#!/usr/bin/env bash
# ============================================================================
# boot_pmos.sh – Boot postmarketOS in QEMU with automatic VNC handling
# ============================================================================
# This script:
#   1. Mounts the .img image, extracts the root UUID.
#   2. Finds a free VNC port (avoids "Address already in use").
#   3. Starts QEMU in the background with -vnc :<port>.
#   4. Waits for QEMU to start, then attempts to launch vncviewer.
#   5. If vncviewer is not found, prints connection instructions.
#
# Logs everything to /tmp/boot_pmos.log
# ============================================================================

set -euo pipefail

LOG_FILE="/tmp/boot_pmos_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"
    [ "$success" = "true" ] && status="SUCCESS"
    echo "[$ts] [$status] $operation: $detail"
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

log_result "script_start" "true" "Starting postmarketOS boot script"

# --- 1. Check image ---
if [ ! -f "$IMG_PATH" ]; then
    log_result "check_image" "false" "$IMG_PATH not found"
    exit 1
fi
log_result "check_image" "true" "Image found: $(ls -lh "$IMG_PATH")"

# --- 2. Find free loop device ---
LOOP_DEV=$(sudo losetup -f)
if [ -z "$LOOP_DEV" ]; then
    log_result "find_loop" "false" "No free loop device"
    exit 1
fi
log_result "find_loop" "true" "Using $LOOP_DEV"

# --- 3. Set up loop device ---
sudo losetup -P "$LOOP_DEV" "$IMG_PATH" || {
    log_result "losetup" "false" "Failed to set up loop device"
    exit 1
}
log_result "losetup" "true" "Loop device $LOOP_DEV attached"

# --- 4. Detect root partition ---
ROOT_PART=""
for part in "${LOOP_DEV}p2" "${LOOP_DEV}p3" "${LOOP_DEV}p4"; do
    if [ -e "$part" ]; then
        log_result "detect_root" "true" "Checking $part"
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

# --- 5. Mount root and get UUID ---
sudo mount "$ROOT_PART" "$MOUNT_POINT"
log_result "mount_root" "true" "Mounted $ROOT_PART"

UUID=$(sudo blkid -s UUID -o value "$ROOT_PART")
FSTYPE=$(sudo blkid -s TYPE -o value "$ROOT_PART")
if [ -z "$UUID" ]; then
    log_result "get_uuid" "false" "Could not get UUID"
    exit 1
fi
log_result "get_uuid" "true" "UUID=$UUID, FSTYPE=$FSTYPE"

# --- 6. Ensure kernel and initrd are extracted ---
EFI_PART="${LOOP_DEV}p1"
if [ ! -f "$KERNEL_COPY" ] || [ ! -f "$INITRD_COPY" ]; then
    log_result "extract_kernel" "true" "Extracting from EFI partition"
    sudo mount "$EFI_PART" "$MOUNT_POINT" || {
        log_result "mount_efi" "false" "Could not mount EFI"
        exit 1
    }
    sudo cp "$MOUNT_POINT/vmlinuz" "$KERNEL_COPY"
    sudo cp "$MOUNT_POINT/initramfs" "$INITRD_COPY"
    sudo umount "$MOUNT_POINT"
fi
log_result "check_kernel" "true" "Kernel and initrd ready"

# --- 7. Unmount and detach loop ---
sudo umount "$MOUNT_POINT" || true
trap - EXIT
sudo losetup -d "$LOOP_DEV" || true

# --- 8. Find free VNC port ---
find_free_vnc_port() {
    local port=5900
    while [ $port -le 5910 ]; do
        if ! ss -lnt | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    echo "0"
    return 1
}
VNC_PORT=$(find_free_vnc_port)
if [ "$VNC_PORT" -eq 0 ]; then
    log_result "vnc_port" "false" "No free VNC port (5900-5910)"
    exit 1
fi
VNC_DISPLAY=$((VNC_PORT - 5900))
log_result "vnc_port" "true" "Using VNC port $VNC_PORT (display :$VNC_DISPLAY)"

# --- 9. Build QEMU command ---
QEMU_CMD="qemu-system-x86_64 -m 4096 -smp 2 -kernel \"$KERNEL_COPY\" -initrd \"$INITRD_COPY\" -append \"nomodeset xforcevesa root=UUID=$UUID rootfstype=$FSTYPE rootdelay=5\" -nic user -vga std -vnc :$VNC_DISPLAY"

log_result "qemu_command" "true" "Command built"

echo ""
echo "========================================="
echo "✅ Boot parameters ready."
echo "   UUID: $UUID"
echo "   VNC display: :$VNC_DISPLAY (port $VNC_PORT)"
echo "   Kernel: $KERNEL_COPY"
echo "   Initrd: $INITRD_COPY"
echo ""
echo "🚀 Starting QEMU..."
echo "========================================="

# --- 10. Start QEMU in background ---
eval "$QEMU_CMD" &
QEMU_PID=$!
log_result "qemu_start" "true" "QEMU started with PID $QEMU_PID"

# Wait a moment for QEMU to initialise
sleep 3

# --- 11. Try to launch vncviewer ---
if command -v vncviewer &>/dev/null; then
    echo ""
    echo "🔌 Launching vncviewer to connect to localhost:$VNC_PORT ..."
    vncviewer "localhost:$VNC_PORT" &
else
    echo ""
    echo "⚠️  vncviewer not found. Please install TigerVNC:"
    echo "   sudo dnf install -y tigervnc"
    echo ""
    echo "📌 Then connect to:"
    echo "   vncviewer localhost:$VNC_PORT"
fi

echo ""
echo "📄 Full log: $LOG_FILE"
echo "========================================="
echo "Press Ctrl+C to stop QEMU when done."

# --- 12. Wait for QEMU to finish ---
wait $QEMU_PID

exit 0
