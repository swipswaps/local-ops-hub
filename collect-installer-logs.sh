#!/usr/bin/env bash
echo "=== BEGIN INSTALLER DIAGNOSTIC ==="

echo "--- 1. Calamares logs ---"
if [ -d /var/log/calamares ]; then
    find /var/log/calamares -type f -exec sh -c 'echo "== {} =="; cat {}' \;
else
    echo "No /var/log/calamares directory found."
fi

echo "--- 2. Other installer logs ---"
if [ -d /var/log/installer ]; then
    find /var/log/installer -type f -exec sh -c 'echo "== {} =="; cat {}' \;
else
    echo "No /var/log/installer directory found."
fi

echo "--- 3. dmesg recent errors ---"
dmesg | grep -E "error|fail|segfault|oom|corrupt" | tail -50

echo "--- 4. Partition layout of target disk (/dev/vdb) ---"
lsblk /dev/vdb
fdisk -l /dev/vdb

echo "--- 5. Mounted filesystems (to see if /target exists) ---"
mount | grep -E "/target|/mnt"

echo "--- 6. Check if /dev/vdb has any existing partitions ---"
parted /dev/vdb print 2>/dev/null || echo "parted not installed or disk empty"

echo "=== END DIAGNOSTIC ==="
