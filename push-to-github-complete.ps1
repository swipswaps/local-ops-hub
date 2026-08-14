# ------------------------------------------------------------
# push-to-github-complete.ps1
# Complete one-shot push with all safeguards
# ------------------------------------------------------------

$REPO_NAME = "fedora-vm-setup"
$USERNAME = gh api user --jq ".login"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " GitHub Push - Complete" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# --- 1. Check gh auth ---
Write-Host ""
Write-Host "[1/7] Checking GitHub authentication..." -ForegroundColor Yellow
if (-not (gh auth status 2>$null)) {
    Write-Host "ERROR: Not logged in. Run: gh auth login" -ForegroundColor Red
    exit 1
}
Write-Host "SUCCESS: GitHub CLI authenticated as: $(gh api user --jq ".login")" -ForegroundColor Green

# --- 2. Check current directory ---
Write-Host ""
Write-Host "[2/7] Checking current directory..." -ForegroundColor Yellow
$currentDir = Get-Location
Write-Host "   Directory: $currentDir" -ForegroundColor White

# --- 3. Check if there are files to push ---
Write-Host ""
Write-Host "[3/7] Checking files to push..." -ForegroundColor Yellow
$files = Get-ChildItem -File -Recurse | Where-Object { $_.Name -notmatch "\.(exe|msi|iso|vdi|vbox|vbox-prev|log)$" }
$fileCount = ($files | Measure-Object).Count

if ($fileCount -eq 0) {
    Write-Host "WARNING: No files found in this directory to push." -ForegroundColor Yellow
    Write-Host "   Make sure you"'"re in the right directory." -ForegroundColor White
    Write-Host "   Current directory: $currentDir" -ForegroundColor White
    exit 1
}
Write-Host "   Found $fileCount files to push." -ForegroundColor Green

# Show files
$files | Select-Object -First 10 | ForEach-Object { Write-Host "     - $($_.Name)" -ForegroundColor White }
if ($fileCount -gt 10) { Write-Host "     ... and $($fileCount - 10) more" -ForegroundColor White }

# --- 4. Initialize git ---
Write-Host ""
Write-Host "[4/7] Initializing git..." -ForegroundColor Yellow
if (-not (Test-Path ".git")) {
    git init
    Write-Host "   SUCCESS: Git initialized" -ForegroundColor Green
} else {
    Write-Host "   SUCCESS: Git already initialized" -ForegroundColor Green
}

# --- 5. Create .gitignore ---
Write-Host ""
Write-Host "[5/7] Creating .gitignore..." -ForegroundColor Yellow
@"
# Windows
Thumbs.db
*.exe
*.msi
*.iso
*.vdi
*.vbox
*.vbox-prev
*.vhd
*.vhdx

# Linux
*.o
*.so
*.ko
*.log
*.tmp
*.zst
*.zck
*.swp
*.swo

# Temporary
/tmp/
*.tmp
*~
#*
~*
*.log
/var/
/logs/

# Misc
.DS_Store
*.bak
*.backup
*.orig
*.rej
*.patch
.env
venv/
__pycache__/
*.pyc
*.pyo

# IDE
.vscode/
.idea/
*.iml
"@ | Out-File -FilePath ".gitignore" -Encoding utf8
Write-Host "   SUCCESS: .gitignore created" -ForegroundColor Green

# --- 6. Create README.md ---
Write-Host ""
Write-Host "[6/7] Creating README.md..." -ForegroundColor Yellow
@"
# Fedora VM Setup Scripts

Complete collection of scripts to set up a Fedora VM in VirtualBox on Windows.

## Scripts

| Script | Description |
|--------|-------------|
| Install-VirtualBox.ps1 | Downloads and installs VirtualBox silently |
| Create-FedoraVM.ps1 | Creates a Fedora VM with proper settings |
| Setup-VirtualBox-Fedora.ps1 | All-in-one: install VirtualBox + create Fedora VM |
| Post-Install-Fedora.ps1 | Windows instructions for post-install setup |
| Post-Install-Fedora.sh | Linux bash script to run inside the VM |
| audit_full.sh | Full system audit for VirtualBox display issues |
| fix_blocker.sh | Builds vboxvideo module manually |
| apply_resolution.sh | Applies 1920x1080 resolution |

## Quick Start

1. Open PowerShell as Administrator
2. Run: .\Setup-VirtualBox-Fedora.ps1
3. Complete Fedora installation in the VM
4. Inside the VM, run: ./Post-Install-Fedora.sh

## Requirements

- Windows 10/11
- PowerShell (Run as Administrator)
- Internet connection

## Notes

- During Fedora installation, create a user with a password - this is your only way to log in later
- After installation, the ISO will be auto-detached
- VirtualBox Guest Additions are installed automatically

## Troubleshooting

If you see vboxvideo.ko missing errors, run:
./fix_blocker.sh
./apply_resolution.sh

## License

MIT
"@ | Out-File -FilePath "README.md" -Encoding utf8
Write-Host "   SUCCESS: README.md created" -ForegroundColor Green

# --- 7. Add and commit ---
Write-Host ""
Write-Host "[7/7] Adding, committing, and pushing..." -ForegroundColor Yellow

# Add all files (except those in .gitignore)
git add .

# Check if there's anything to commit
$status = git status --porcelain
if (-not $status) {
    Write-Host "   No changes to commit. Skipping commit." -ForegroundColor Yellow
} else {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "Complete Fedora VM setup scripts - $timestamp"
    Write-Host "   SUCCESS: Commit created" -ForegroundColor Green
}

# Create repo on GitHub
Write-Host "   Creating repository on GitHub..." -ForegroundColor White
gh repo create $REPO_NAME --public --source=. --remote=origin --push 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "   Repository may already exist. Setting remote..." -ForegroundColor Yellow
    git remote add origin "https://github.com/$USERNAME/$REPO_NAME.git" 2>$null
}

# Push
Write-Host "   Pushing to GitHub..." -ForegroundColor White
git branch -M main
git push -u origin main 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "   Push failed. Trying force push..." -ForegroundColor Yellow
    git push -u origin main --force
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "SUCCESS: Repository pushed successfully!" -ForegroundColor Green
Write-Host "   https://github.com/$USERNAME/$REPO_NAME" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Green

# Show what was pushed
Write-Host ""
Write-Host "Files in repository:" -ForegroundColor Yellow
git ls-tree -r main --name-only | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
