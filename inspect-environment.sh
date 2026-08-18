#!/bin/sh
# ============================================================================
# inspect-environment.sh – Diagnostic: what user/display/session is running?
# ============================================================================

echo "=== USER / ID ==="
id
whoami
echo ""

echo "=== RUNNING PROCESSES (ps) ==="
ps
echo ""

echo "=== DISPLAY ==="
echo "DISPLAY=$DISPLAY"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
ls -la /tmp/.X11-unix/ 2>/dev/null || echo "No X11 socket"
echo ""

echo "=== DBUS ==="
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
echo ""

echo "=== MOUNTS ==="
mount | grep -E "vda|vdb|sda|sdb|tmpfs"
echo ""

echo "=== BLOCK DEVICES ==="
ls -la /dev/vd* /dev/sd* 2>/dev/null || echo "No block devices found"
echo ""

echo "=== INSTALLER CHECK ==="
which os-installer 2>/dev/null || echo "os-installer not found"
ls -la /usr/bin/os-installer 2>/dev/null || echo "os-installer binary not present"
echo ""

echo "=== POLKIT ==="
ps aux | grep -E "polkit|pkexec" | grep -v grep || echo "No polkit processes"
echo ""

echo "=== SESSION BUS (list all users) ==="
ls -la /run/user/ 2>/dev/null || echo "No /run/user/"
