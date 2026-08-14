#Requires -RunAsAdministrator
# ------------------------------------------------------------
# Setup-VirtualBox-Fedora.ps1
# Complete setup: Install VirtualBox + Create Fedora VM
# ------------------------------------------------------------

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " VirtualBox + Fedora Complete Setup" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# --- CONFIGURATION ---
$VMName = "FedoraDesktop"
$RAM = 4096
$CPU = 2
$VRAM = 128
$DiskSize = 25600  # 25 GB
$VB_VERSION = "7.1.6"
$VB_BUILD = "167084"
$ISOUrl = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-Live-44-1.7.x86_64.iso"
$ISODest = "$env:TEMP\Fedora-Workstation-Live-44-1.7.x86_64.iso"

$vboxManage = "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe"

# --- PART 1: Install VirtualBox ---
Write-Host "[1/4] Installing VirtualBox..." -ForegroundColor Yellow

if (Test-Path $vboxManage) {
    $version = & $vboxManage --version
    Write-Host "   ✅ VirtualBox already installed (Version: $version)" -ForegroundColor Green
} else {
    $VB_URL = "https://download.virtualbox.org/virtualbox/$VB_VERSION/VirtualBox-$VB_VERSION-$VB_BUILD-Win.exe"
    $VB_INSTALLER = "$env:TEMP\VirtualBox-Installer.exe"
    
    Write-Host "   📥 Downloading VirtualBox $VB_VERSION..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $VB_URL -OutFile $VB_INSTALLER -UseBasicParsing
    
    Write-Host "   🔧 Installing VirtualBox..." -ForegroundColor Yellow
    Start-Process -FilePath $VB_INSTALLER -ArgumentList "--silent" -Wait
    
    Remove-Item $VB_INSTALLER -Force -ErrorAction SilentlyContinue
    
    if (-not (Test-Path $vboxManage)) {
        Write-Host "   ❌ VirtualBox installation failed." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        return
    }
    Write-Host "   ✅ VirtualBox installed successfully." -ForegroundColor Green
}

# --- PART 2: Download Fedora ISO ---
Write-Host ""
Write-Host "[2/4] Downloading Fedora ISO..." -ForegroundColor Yellow

if (Test-Path $ISODest) {
    Write-Host "   ✅ ISO already downloaded: $ISODest" -ForegroundColor Green
} else {
    Write-Host "   ⏳ Downloading Fedora ISO (this may take 10-15 minutes)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ISOUrl -OutFile $ISODest -UseBasicParsing
    if (-not (Test-Path $ISODest)) {
        Write-Host "   ❌ ISO download failed." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        return
    }
    Write-Host "   ✅ ISO downloaded: $ISODest" -ForegroundColor Green
}

# --- PART 3: Create VM ---
Write-Host ""
Write-Host "[3/4] Creating VM '$VMName'..." -ForegroundColor Yellow

# Remove existing VM
$existingVM = & $vboxManage list vms | Select-String $VMName
if ($existingVM) {
    Write-Host "   ⚠️  VM '$VMName' already exists. Removing..." -ForegroundColor Yellow
    & $vboxManage unregistervm $VMName --delete 2>$null
}

# Create VM
& $vboxManage createvm --name $VMName --ostype Fedora_64 --register

# Configure VM
& $vboxManage modifyvm $VMName `
    --memory $RAM `
    --cpus $CPU `
    --ioapic on `
    --nestedpaging on `
    --firmware efi `
    --graphicscontroller vmsvga `
    --vram $VRAM `
    --accelerate3d off `
    --clipboard bidirectional `
    --draganddrop bidirectional `
    --audio-driver dsound `
    --audiocontroller hda `
    --nic1 nat

# Create storage
& $vboxManage storagectl $VMName --name "SATA" --add sata --controller IntelAhci
$diskPath = "$env:USERPROFILE\VirtualBox VMs\$VMName\$VMName.vdi"
& $vboxManage createmedium disk --filename $diskPath --size $DiskSize --variant Standard
& $vboxManage storageattach $VMName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $diskPath

# Attach ISO
& $vboxManage storageattach $VMName --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium $ISODest

Write-Host "   ✅ VM created successfully." -ForegroundColor Green

# --- PART 4: Start VM ---
Write-Host ""
Write-Host "[4/4] Starting VM..." -ForegroundColor Yellow
& $vboxManage startvm $VMName

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "📀 VM: $VMName" -ForegroundColor Yellow
Write-Host "💾 RAM: $RAM MB, CPU: $CPU cores" -ForegroundColor Yellow
Write-Host "📦 Disk: $DiskSize MB (dynamic)" -ForegroundColor Yellow
Write-Host ""
Write-Host "📀 Fedora ISO is attached." -ForegroundColor Yellow
Write-Host "   Complete the Fedora installer in the VM window." -ForegroundColor Yellow
Write-Host "   IMPORTANT: During installation, create a user with a password." -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

Read-Host "`nPress Enter to exit"
