<#
.SYNOPSIS
    Installation and provisioning script for LocalDoby on Windows.
.DESCRIPTION
    Sets up the local offline AI environment under ~\.localdoby, pulls pre-compiled 
    Windows binaries, provisions a virtual environment, and handles pipeline models.
    This version includes an integrated wrapper that manages the llmserver lifecycle.
#>

$ErrorActionPreference = "Stop"

# Parse incoming arguments for the clean flag
$CleanMode = $false
foreach ($arg in $args) {
    if ($arg -eq "--clean" -or $arg -eq "-clean") { $CleanMode = $true }
}

$TARGET_DIR = Join-Path $HOME ".localdoby"
$BIN_DIR    = Join-Path $TARGET_DIR "bin"
$LIB_DIR    = Join-Path $TARGET_DIR "lib"
$MODEL_DIR  = Join-Path $TARGET_DIR "models"
$VENV_DIR   = Join-Path $TARGET_DIR "venv"
$DB_DIR     = Join-Path $TARGET_DIR "db"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "         Installing LocalDoby for Windows           " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# PHASE 0 & 1: PURGE & DIRECTORY INITIALIZATION
# ---------------------------------------------------------------------------
if ($CleanMode) {
    $PathsToPurge = @($BIN_DIR, $LIB_DIR, $MODEL_DIR, $VENV_DIR)
    foreach ($Path in $PathsToPurge) {
        if (Test-Path $Path) { Remove-Item -Recurse -Force $Path }
    }
}
foreach ($Dir in @($BIN_DIR, $LIB_DIR, $MODEL_DIR, $DB_DIR)) {
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
}

# ---------------------------------------------------------------------------
# PHASE 2: BINARY LAYOUT RETRIEVAL
# ---------------------------------------------------------------------------
$TEMP_WORKSPACE = Join-Path $([System.IO.Path]::GetTempPath()) "localdoby_install_$(Get-Random)"
try {
    git clone https://github.com/jon004/localdoby-binaries.git $TEMP_WORKSPACE
    $DIST = Join-Path $TEMP_WORKSPACE "windows"
    if (Test-Path "$DIST\bin") { Copy-Item -Recurse -Force "$DIST\bin\*" $BIN_DIR }
    if (Test-Path "$DIST\lib") { Copy-Item -Recurse -Force "$DIST\lib\*" $LIB_DIR }
    if (Test-Path "$DIST\requirements.txt") { Copy-Item -Force "$DIST\requirements.txt" $TARGET_DIR }
} finally {
    if (Test-Path $TEMP_WORKSPACE) { Remove-Item -Recurse -Force $TEMP_WORKSPACE }
}

# ---------------------------------------------------------------------------
# PHASE 3: PYTHON ENVIRONMENT & REQUIREMENTS
# ---------------------------------------------------------------------------
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "Python 3.11+ required." }
if (-not (Test-Path $VENV_DIR)) { & python -m venv $VENV_DIR }

$VENV_PIP = Join-Path $VENV_DIR "Scripts\pip.exe"
& (Join-Path $VENV_DIR "Scripts\python.exe") -m pip install --upgrade pip
& $VENV_PIP install sentence-transformers torch pandas scikit-learn huggingface_hub

# ---------------------------------------------------------------------------
# PHASE 4: EXECUTION WRAPPER (INTEGRATED LLMSERVER MANAGEMENT)
# ---------------------------------------------------------------------------
$WRAPPER_PATH = Join-Path $BIN_DIR "document-tools.ps1"
$WrapperContent = @'
$ErrorActionPreference = "Stop"
$TARGET_DIR = Join-Path $HOME ".localdoby"
$BIN_DIR    = Join-Path $TARGET_DIR "bin"
$LIB_DIR    = Join-Path $TARGET_DIR "lib"
$MODEL_DIR  = Join-Path $TARGET_DIR "models"
$VENV_DIR   = Join-Path $TARGET_DIR "venv"
$DB_DIR     = Join-Path $TARGET_DIR "db"

# Lifecycle Management: Start llmserver if not running
$SERVER_EXE = Join-Path $BIN_DIR "llmserver.exe"
if (-not (Get-Process -Name "llmserver" -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $SERVER_EXE -ArgumentList "--port 8080" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

# Execution
$env:PYTHONPATH = $LIB_DIR
$env:MODEL_PATH = $MODEL_DIR
$env:DB_PATH    = Join-Path $DB_DIR "localdoby.db"
& (Join-Path $VENV_DIR "Scripts\python.exe") (Join-Path $LIB_DIR "main.py") $args
'@
$WrapperContent | Out-File -FilePath $WRAPPER_PATH -Encoding utf8

# ---------------------------------------------------------------------------
# PHASE 5: MODEL ASSET SYNCHRONIZATION
# ---------------------------------------------------------------------------
function Sync-PublicModelAsset {
    param ([string]$DownloadUrl, [string]$RelativeTargetFile)
    $DestinationFile = Join-Path $MODEL_DIR $RelativeTargetFile
    $ParentDir = Split-Path $DestinationFile -Parent
    if (-not (Test-Path $ParentDir)) { New-Item -ItemType Directory -Force $ParentDir | Out-Null }
    if (-not (Test-Path $DestinationFile)) {
        (New-Object System.Net.WebClient).DownloadFile($DownloadUrl, $DestinationFile)
    }
}
# (Include your Sync-PublicModelAsset calls here as in the original script)

Write-Host "Installation Complete. Run: powershell -File `"$WRAPPER_PATH`"" -ForegroundColor Green
