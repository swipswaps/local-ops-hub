#!/usr/bin/env bash
# ============================================================================
# boot-pmos-virtio-tablet-fixed_0003.sh
# - Forces a getty on ttyS0 with autologin
# - Uses both graphical and serial consoles
# - Pre-flight lock detection retained
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

find_image_qemu() {
	pgrep -f "qemu-system-x86_64.*${IMG}" 2>/dev/null | tr '\n' ' ' | sed 's/^ *//;s/ *$//'
}

kill_pids() {
	local pid_list="$1"
	for pid in $pid_list; do
		if kill -0 "$pid" 2>/dev/null; then
			kill -9 "$pid" 2>/dev/null || true
		fi
	done
}

echo "🔍 Pre-flight check: scanning for disk lock holders..."
LOCK_PIDS=$(find_lock_holders)
IMG_PIDS=$(find_image_qemu)
ALL_PIDS=$(echo "$LOCK_PIDS $IMG_PIDS" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//')

if [ -n "$ALL_PIDS" ]; then
	echo ""
	echo "⚠️  STALE QEMU PROCESSES DETECTED"
	for pid in $ALL_PIDS; do
		local cmdline=""
		if [ -r "/proc/$pid/cmdline" ]; then
			cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-80)
		fi
		printf "   • PID %-6s %s\n" "$pid" "$cmdline"
	done
	echo ""
	echo "   If you proceed, these processes will be force-killed."
	read -r -t 30 -p "   Kill stale processes and continue boot? [y/N] " response || true
	echo ""
	case "${response:-N}" in
		[yY][eE][sS]|[yY])
			echo "   Terminating stale processes..."
			kill_pids "$ALL_PIDS"
			sleep 2
			REMAINING=$(find_lock_holders)
			if [ -n "$REMAINING" ]; then
				echo "   ❌ LOCK STILL HELD by PIDs: $REMAINING"
				echo "   Try: sudo fuser -k $NEWDISK"
				exit 1
			fi
			echo "   ✅ All locks released."
			;;
		*)
			echo "   ❌ Boot aborted by user."
			exit 1
			;;
	esac
else
	echo "   ✅ No lock holders detected — disk is free."
fi

echo ""
echo "🚀 Booting with dual console (ttyS0 + tty0) and autologin on serial..."
exec qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -cpu host \
  -m 4G \
  -drive file="$IMG",if=virtio,format=raw \
  -drive file="$NEWDISK",if=virtio,format=qcow2 \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "root=/dev/vda2 rootwait console=tty0 console=ttyS0 systemd.getty_autologin=user" \
  -usb \
  -device usb-tablet \
  -vnc :0 \
  -serial stdio \
  -vga virtio
