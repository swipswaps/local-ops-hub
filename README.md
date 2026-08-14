# Fedora VM Setup Scripts

Complete collection of scripts to set up a Fedora VM in VirtualBox on Windows.

---

## 📋 Prerequisites

- Windows 10 or Windows 11
- Administrator access
- Internet connection
- At least 30 GB free disk space
- At least 8 GB RAM (16 GB recommended)

---

## 🚀 Complete Step-by-Step Guide

### Step 1: Open PowerShell as Administrator

**Method 1: Start Menu**
1. Click the Start button (Windows icon) in the bottom-left corner
2. Type PowerShell
3. Right-click on Windows PowerShell in the search results
4. Select Run as administrator
5. Click Yes when the User Account Control (UAC) prompt appears

**Method 2: Run Dialog**
1. Press Windows + R on your keyboard
2. Type powershell in the Run dialog
3. Press Ctrl + Shift + Enter (this opens it as administrator)
4. Click Yes on the UAC prompt

**Method 3: Windows Terminal**
1. Open Windows Terminal
2. Click the dropdown arrow next to the tabs
3. Select Windows PowerShell
4. Click the dropdown arrow again
5. Select Settings
6. Under Profiles Windows PowerShell, toggle Run this profile as administrator
7. Click Save and open a new tab

**Method 4: Win+X Menu**
1. Press Windows + X on your keyboard
2. Select Windows PowerShell (Admin) or Terminal (Admin)
3. Click Yes on the UAC prompt

---

### Step 2: Check if Git is Installed

In the PowerShell window, type:

git --version

If Git is installed, you'll see: git version 2.55.0.windows.3

If Git is NOT installed, continue to Step 3.

---

### Step 3: Install Git

**Option A: Install with winget (Recommended)**

winget install --id Git.Git -e --source winget

**Option B: Install manually**
1. Open your browser
2. Go to: https://git-scm.com/download/win
3. Download the 64-bit version
4. Run the installer (use default settings)

**After installation, refresh the PATH:**

`$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")`

**Verify:**

git --version

---

### Step 4: Install GitHub CLI (if needed)

**Option A: Install with winget**

winget install --id GitHub.cli

**Option B: Install manually**
1. Go to: https://github.com/cli/cli/releases
2. Download gh_*_windows_amd64.msi
3. Run the installer

**After installation, refresh the PATH:**

`$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")`

**Verify:**

gh --version

---

### Step 5: Set Your Git Identity

**Replace your-username with your actual GitHub username:**

git config --global user.name "your-username"
git config --global user.email "your-username@users.noreply.github.com"

**Example:**

git config --global user.name "swipswaps"
git config --global user.email "swipswaps@users.noreply.github.com"

---

### Step 6: Clone the Repository

**Option A: Clone with Git**

git clone https://github.com/swipswaps/fedora-vm-setup.git
cd fedora-vm-setup

**Option B: Download ZIP**
1. Go to: https://github.com/swipswaps/fedora-vm-setup
2. Click the green Code button
3. Select Download ZIP
4. Extract and open PowerShell in that folder

---

### Step 7: Allow Scripts to Run

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

---

### Step 8: Run the Complete Setup

.\Setup-VirtualBox-Fedora.ps1

**What this does:**
- Downloads and installs VirtualBox (if not installed)
- Downloads the Fedora ISO
- Creates a Fedora VM with 4 GB RAM, 2 CPU cores, 128 MB video RAM, 25 GB disk
- Attaches the ISO and starts the VM

The script will take several minutes to complete.

---

### Step 9: Install Fedora in the VM

1. The VM boots into Fedora Live
2. Click Install to Hard Drive on the desktop
3. Follow the installer wizard
4. IMPORTANT: Create a user with a password - this is your only way to log in later
5. Wait for installation to complete
6. Remove the ISO from the virtual drive
7. Shut down the VM

---

### Step 10: Start the VM and Log In

1. Start the VM from VirtualBox Manager
2. Log in with your username and password

---

### Step 11: Install Guest Additions (Inside the VM)

Open a terminal (Ctrl+Alt+T) and run:

sudo dnf install -y kernel-devel kernel-headers gcc make perl dkms

# Insert Guest Additions CD from VirtualBox menu: Devices → Insert Guest Additions CD image...

sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom 2>/dev/null || sudo mount /dev/sr0 /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot

---

### Step 12: Fix Display Resolution (Inside the VM)

After reboot, open a terminal:

pkill VBoxClient
VBoxClient --clipboard &
VBoxClient --vmsvga &

xrandr --newmode "1920x1080"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync
xrandr --addmode None-1 1920x1080
xrandr --output None-1 --mode 1920x1080

**To make it permanent:**

cat > ~/.xprofile <<'EOF'
#!/bin/bash
xrandr --newmode "1920x1080"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync
xrandr --addmode None-1 1920x1080
xrandr --output None-1 --mode 1920x1080
pkill VBoxClient 2>/dev/null
VBoxClient --clipboard &
VBoxClient --vmsvga &
EOF
chmod +x ~/.xprofile

---

## 🔧 Troubleshooting

**"Running scripts is disabled"**

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

**"vboxvideo.ko missing"**

sudo /sbin/rcvboxadd quicksetup $(uname -r)
sudo reboot

**"VBoxClient not found"**

find /opt -name VBoxClient 2>/dev/null
/opt/VBoxGuestAdditions-*/bin/VBoxClient --clipboard
/opt/VBoxGuestAdditions-*/bin/VBoxClient --vmsvga

**Clipboard not working**

pkill VBoxClient
VBoxClient --clipboard &

**GRUB menu not showing**

sudo grub2-mkconfig -o /boot/grub2/grub.cfg

**Black screen after kernel update**

Boot from older kernel, then:
sudo /sbin/rcvboxadd quicksetup all
sudo reboot

**git or gh not recognized**

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

---

## 📁 Scripts in This Repository

| Script | Purpose |
|--------|---------|
| Install-VirtualBox.ps1 | Downloads and installs VirtualBox silently |
| Create-FedoraVM.ps1 | Creates a Fedora VM with proper settings |
| Setup-VirtualBox-Fedora.ps1 | All-in-one: install VirtualBox + create VM |
| Post-Install-Fedora.ps1 | Windows instructions for post-install setup |
| Post-Install-Fedora.sh | Linux bash script to run inside the VM |

---

## 📌 Important Notes

- During Fedora installation, create a user with a password - this is your only way to log in later
- After installation, remove the ISO from the virtual drive
- Switch to Xorg at login for better compatibility

---

## 📄 License

MIT License - feel free to use and modify!

---

## 🔗 Links

- VirtualBox: https://www.virtualbox.org/
- Fedora: https://getfedora.org/
- GitHub CLI: https://cli.github.com/

Happy virtualizing! 🐧
