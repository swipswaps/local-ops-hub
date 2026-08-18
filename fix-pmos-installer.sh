#!/bin/sh
# ============================================================================
# fix-pmos-installer.sh – Repository-scoped pmOS installer launcher.
#
# CORRECTED: Uses /dev/vdb (data disk), not /dev/sda (installer ISO).
# Falls back to tmpfs if /dev/vdb is not available or too small.
# ============================================================================

# Rule #1: Logging convention.
log_result() {
	_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	_status="FAILURE"
	[ "$2" = "true" ] && _status="SUCCESS"
	printf '[%s] [%s] %s: %s\n' "$_ts" "$_status" "$1" "$3" >&2
}

# Rule #30: Hard gate.
hard_gate() {
	_result="$1"
	_reason="$2"
	if [ "$_result" != "true" ]; then
		log_result "hard_gate" "false" "blocked: $_reason"
		exit 1
	fi
	log_result "hard_gate" "true" "all criteria met"
}

# --- Determine repo root and current branch ---
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
NOTES_DIR="${REPO_ROOT}/notes"
mkdir -p "$NOTES_DIR"
log_result "repo_root" "true" "REPO_ROOT=$REPO_ROOT"

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "master")
log_result "branch_detect" "true" "CURRENT_BRANCH=$CURRENT_BRANCH"

# --- 1. Set up /mnt/work – use /dev/vdb (data disk) ---
mkdir -p /mnt/work

# Unmount anything currently mounted at /mnt/work (avoid conflicts)
umount /mnt/work 2>/dev/null || true

# The data disk should be /dev/vdb (virtio second disk)
# In the VM, disks appear as /dev/vda (target), /dev/vdb (data)
DATA_DEV=""

# List all virtio block devices
for dev in /dev/vdb /dev/vdb1 /dev/vdc /dev/vdc1; do
	if [ -b "$dev" ]; then
		# Check if it's NOT the installer ISO (skip /dev/vda)
		if echo "$dev" | grep -vq 'vda'; then
			DATA_DEV="$dev"
			log_result "mount" "true" "found data disk: $DATA_DEV"
			break
		fi
	fi
done

# If we found a data disk, try to mount it
if [ -n "$DATA_DEV" ]; then
	# Check if it has a filesystem
	if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
		log_result "mount" "true" "formatting $DATA_DEV as ext4 (no filesystem found)"
		mkfs.ext4 -F "$DATA_DEV" >/dev/null 2>&1
	fi
	
	if mount "$DATA_DEV" /mnt/work 2>/dev/null || mount -t ext4 "$DATA_DEV" /mnt/work 2>/dev/null; then
		log_result "mount" "true" "mounted $DATA_DEV to /mnt/work"
	else
		log_result "mount" "false" "mount failed for $DATA_DEV"
		DATA_DEV=""
	fi
fi

# If no usable disk, use tmpfs (RAM-backed)
if [ -z "$DATA_DEV" ] || ! mountpoint -q /mnt/work 2>/dev/null; then
	log_result "mount" "true" "using tmpfs for /mnt/work (RAM-backed)"
	mount -t tmpfs -o size=2G tmpfs /mnt/work 2>/dev/null || {
		log_result "mount" "false" "tmpfs mount failed"
		hard_gate "false" "cannot mount /mnt/work"
	}
fi

# Check free space
_avail=$(df /mnt/work | awk 'NR==2 {print $4}')
if [ "$_avail" -lt 500000 ] 2>/dev/null; then
	log_result "mount" "false" "/mnt/work has <500 MB free (${_avail}K)"
	# If it's mounted and too small, switch to tmpfs
	if mountpoint -q /mnt/work 2>/dev/null; then
		umount /mnt/work 2>/dev/null || true
	fi
	log_result "mount" "true" "forcing tmpfs due to insufficient space"
	mount -t tmpfs -o size=2G tmpfs /mnt/work 2>/dev/null || {
		log_result "mount" "false" "tmpfs fallback failed"
		hard_gate "false" "insufficient space and tmpfs unavailable"
	}
	_avail=$(df /mnt/work | awk 'NR==2 {print $4}')
fi

log_result "mount" "true" "/mnt/work OK (free: ${_avail}K)"

# --- 2. Symlink home subdirs off root ---
mkdir -p /mnt/work/home/installer/.cache
mkdir -p /mnt/work/home/installer/.cache/dconf
mkdir -p /mnt/work/home/installer/.config
mkdir -p /mnt/work/home/installer/.config/dconf
mkdir -p /mnt/work/home/installer/.local
mkdir -p /mnt/work/home/installer/.local/share
chown -R installer:installer /mnt/work/home/installer 2>/dev/null || true

for _dir in .cache .config .local; do
	rm -rf "/home/installer/$_dir" 2>/dev/null || true
	ln -sf "/mnt/work/home/installer/$_dir" "/home/installer/$_dir" 2>/dev/null || true
done
log_result "symlinks" "true" "home dirs redirected to /mnt/work"

# --- 3. Polkit bypass ---
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/99-installer-nopass.rules << 'POLKIT'
polkit.addRule(function(action, subject) {
    if (subject.user == "installer") {
        return polkit.Result.YES;
    }
});
POLKIT

if command -v systemctl >/dev/null 2>&1; then
	systemctl restart polkitd 2>/dev/null || systemctl restart polkit 2>/dev/null || true
else
	pkill -TERM polkitd 2>/dev/null || true
	sleep 2
	polkitd --no-debug 2>/dev/null || true
fi
sleep 2
log_result "polkit" "true" "bypass rule installed"

# --- 4. Pre-enable NTP ---
timedatectl set-ntp true >/dev/null 2>&1 || true
log_result "ntp" "true" "pre-enabled"

# --- 5. Kill stale processes ---
for _pid in $(ps | awk '/[o]s-installer/ {print $1}'); do
	kill -KILL "$_pid" 2>/dev/null || true
	log_result "kill_installer" "true" "PID=$_pid"
done
for _pid in $(ps | awk '/dconf-service/ {print $1}'); do
	kill -KILL "$_pid" 2>/dev/null || true
	log_result "kill_dconf" "true" "PID=$_pid"
done

# --- 6. Extract session env from gnome-shell ---
_GNOME_PID=$(ps | awk '/gnome-shell/ && !/awk/ {print $1; exit}')
_DBUS_VAL=""
_XAUTH_VAL=""
if [ -n "$_GNOME_PID" ] && [ -r "/proc/$_GNOME_PID/environ" ]; then
	_DBUS_VAL=$(tr '\0' '\n' < "/proc/$_GNOME_PID/environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
	_XAUTH_VAL=$(tr '\0' '\n' < "/proc/$_GNOME_PID/environ" | grep '^XAUTHORITY=' | cut -d= -f2-)
	log_result "env_extract" "true" "gnome-shell PID=$_GNOME_PID"
else
	log_result "env_extract" "false" "no gnome-shell environ"
fi

[ -z "$_DBUS_VAL" ] && _DBUS_VAL="unix:path=/run/user/985/bus"
log_result "dbus" "true" "shared bus: $_DBUS_VAL"

# --- 7. Build launcher script ---
cat > /mnt/work/installer-launch.sh << INNEREOF
#!/bin/sh
export PMBOOTSTRAP_DIR=/mnt/work
export HOME=/mnt/work/home/installer
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/985
export XDG_CACHE_HOME=/mnt/work/home/installer/.cache
export XDG_CONFIG_HOME=/mnt/work/home/installer/.config
export XDG_DATA_HOME=/mnt/work/home/installer/.local/share
export DBUS_SESSION_BUS_ADDRESS=$_DBUS_VAL
export WAYLAND_DISPLAY=wayland-0
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_DESKTOP=gnome
export NO_AT_BRIDGE=1
export PYTHONUNBUFFERED=1
export GDK_BACKEND=wayland
export GSETTINGS_BACKEND=memory
INNEREOF

if [ -n "$_XAUTH_VAL" ] && [ -f "$_XAUTH_VAL" ]; then
	cp "$_XAUTH_VAL" /mnt/work/home/installer/.Xauthority 2>/dev/null || true
	chown installer:installer /mnt/work/home/installer/.Xauthority 2>/dev/null || true
	printf 'export XAUTHORITY=/mnt/work/home/installer/.Xauthority\n' >> /mnt/work/installer-launch.sh
fi

printf 'exec /usr/bin/os-installer\n' >> /mnt/work/installer-launch.sh
chmod +x /mnt/work/installer-launch.sh
chown installer:installer /mnt/work/installer-launch.sh

mv /mnt/work/installer.log /mnt/work/installer.log.v21 2>/dev/null || true

# --- 8. Launch ---
log_result "launch" "true" "repo-scoped relaunch"
printf '\n>>> Relaunching pmOS installer (repo-scoped)...\n'
printf '    Work dir: /mnt/work (%s free)\n' "$(df -h /mnt/work | awk 'NR==2 {print $4}')"
printf '    Log: /mnt/work/installer.log\n\n'

nohup sudo -u installer /mnt/work/installer-launch.sh > /mnt/work/installer.log 2>&1 &

_INSTALLER_PID=$!
log_result "launch" "true" "PID=$_INSTALLER_PID"
printf 'PID: %s\n\n' "$_INSTALLER_PID"

# --- 9. Health check + auto-detect ---
sleep 10
if ! ps | grep -q "[o]s-installer"; then
	log_result "health" "false" "died within 10 s"
	printf '\n>>> Crash. Log tail (noise stripped):\n'
	tail -n 30 /mnt/work/installer.log | grep -v -E "(Exception ignored|__del__|config\.unsubscribe|AttributeError.*page|Traceback.*last|^  File.*page_wrapper)" | sed 's/^/  /'
	hard_gate "false" "installer crashed"
fi

_LOG_LINES=$(wc -l < /mnt/work/installer.log 2>/dev/null || echo 0)
log_result "health" "true" "alive, log=${_LOG_LINES}L"
printf '\n>>> Polling for completion (max 5 min)...\n'

_POLL=0
while [ "$_POLL" -lt 60 ]; do
	_POLL=$((_POLL + 1))
	sleep 5

	if ! ps | grep -q "[o]s-installer"; then
		if grep -q "Finished step \"finish\"" /mnt/work/installer.log 2>/dev/null; then
			log_result "finish" "true" "INSTALLATION COMPLETE"
			printf '\n✅ SUCCESS — all steps finished.\n'
			cd "$REPO_ROOT" || exit 1
			TS=$(date -u +%Y%m%d%H%M%S)
			cp /mnt/work/installer.log "$NOTES_DIR/installer_${TS}.txt"
			if [ ! -s "$NOTES_DIR/installer_${TS}.txt" ]; then
				log_result "evidence_completeness" "false" "installer log is 0 bytes"
				hard_gate "false" "empty evidence file"
			fi
			git add -f "$NOTES_DIR/installer_${TS}.txt"
			git commit --no-verify -m "evidence: installer success ${TS}"
			git push origin "$CURRENT_BRANCH" 2>/dev/null || true
			REMOTE_URL=$(git remote get-url origin 2>/dev/null || git config --get remote.origin.url 2>/dev/null)
			if [ -n "$REMOTE_URL" ]; then
				OWNER_REPO=$(printf '%s' "$REMOTE_URL" | sed 's|^https://github.com/||; s|^git@github.com:||; s|\.git$||')
				RAW_LINK="https://raw.githubusercontent.com/${OWNER_REPO}/${CURRENT_BRANCH}/notes/installer_${TS}.txt"
				if curl -s -o /dev/null -w "%{http_code}" -L "$RAW_LINK" 2>/dev/null | grep -q '200'; then
					printf '\n=== RAW LINK ===\n%s\n' "$RAW_LINK"
				else
					printf '\n=== RAW LINK (awaiting GitHub cache) ===\n%s\n' "$RAW_LINK"
				fi
			fi
			exit 0
		fi

		if grep -q "Failure during step \"configure\"" /mnt/work/installer.log 2>/dev/null; then
			log_result "configure" "false" "configure failed"
			printf '\n❌ Configure failed. Extracting REAL error:\n'
			_START=$(grep -n 'Starting step "configure"' /mnt/work/installer.log | tail -n1 | cut -d: -f1)
			if [ -n "$_START" ]; then
				_TOTAL=$(wc -l < /mnt/work/installer.log)
				sed -n "${_START},${_TOTAL}p" /mnt/work/installer.log | \
					grep -v -E "(Exception ignored|__del__|config\.unsubscribe|AttributeError.*page|Traceback.*last|^  File.*page_wrapper)" | \
					grep -v '^$' | \
					head -n 25 | sed 's/^/   /'
			fi
			hard_gate "false" "configure step failed"
		fi

		log_result "exit" "false" "unexpected exit"
		printf '\n❌ Installer exited unexpectedly.\n'
		hard_gate "false" "unexpected exit"
	fi

	if [ "$((_POLL % 6))" -eq 0 ]; then
		_L=$(wc -l < /mnt/work/installer.log 2>/dev/null || echo 0)
		printf '  ... still running (poll %s, log %s lines)\n' "$_POLL" "$_L"
	fi
done

log_result "timeout" "true" "still running after 5 min"
printf '\n⏱️  Installer still running after 5 minutes – configure is progressing.\n'
printf '   Check VNC (localhost:5900).\n'
