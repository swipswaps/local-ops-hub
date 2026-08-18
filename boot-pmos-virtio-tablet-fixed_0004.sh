#!/usr/bin/env bash
# ============================================================================
# boot-pmos-virtio-tablet-fixed_0004.sh
# - Boots with init=/bin/sh (immediate root shell)
# - Forces serial console, no systemd clutter
# ============================================================================

IMG="$HOME/Downloads/20260814-1439-postmarketOS-edge-os-installer-10-generic-x86_64-lts.img"
KERNEL="$HOME/Downloads/vmlinuz-pmos"
INITRD="$HOME/Downloads/initramfs-pmos"
NEWDISK="/home/owner/Documents/19fec7a3-8212-81f8-8000-0986b63a411e/repo/pmos-install-disk.qcow2"

find_lock_holders() {
	local pids=""
	if command -v fuser >/dev/null 2>&1; then
		pids=$(fuser "$NEWDISK" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
	fi
	if [ -z "$pids" ] && command -v lsof >/dev/null 2>&1; then
		pids=$(lsof "$NEWDISK" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | tr '\n' ' ')
	fi
	if [ -z "$pids" ]; then
		pids=$(pgrep -f "qemu-system-x86_64" 2>/dev/null | tr '\n' ' ')
	fi
	echo "$pids" | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

kill_pids() {
	local pid_list="$1"
	for pid in $pid_list; do
		if kill -0 "$pid" 2>/dev/null; then
			kill -9 "$pid" 2>/dev/null || true
		fi
	done
}

echo "🔍 Pre-flight check..."
LOCK_PIDS=$(find_lock_holders)
if [ -n "$LOCK_PIDS" ]; then
	echo "   Stale processes: $LOCK_PIDS – killing..."
	kill_pids "$LOCK_PIDS"
	sleep 2
fi
echo "   ✅ Disk free."

echo "🚀 Booting with init=/bin/sh (root shell on ttyS0)..."
exec qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -drive file="$NEWDISK",if=virtio,format=qcow2 \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=ttyS0 init=/bin/sh" \
  -usb \
  -device usb-tablet \
  -vnc :0 \
  -serial stdio \
  -vga virtio
