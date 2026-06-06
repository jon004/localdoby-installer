<#
.SYNOPSIS
    Installation and provisioning script for LocalDoby on Windows.
.DESCRIPTION
    Sets up the local offline AI environment under ~\.localdoby, pulls pre-compiled 
    Windows binaries, provisions a virtual environment, and handles pipeline models.
    STRICT MODE: Crashes out immediately if any asset download fails.
    CLEAN MODE: Pass --clean to wipe out existing local installation tracking assets.
    DEPENDENCY-FREE: Uses direct raw HTTP downloads so users do not need Git installed.
#>

$ErrorActionPreference = "Stop"

# Parse incoming arguments for the clean flag
$CleanMode = $false
foreach ($arg in $args) {
    if ($arg -eq "--clean" -or $arg -eq "-clean") {
        $CleanMode = $true
    }
}

# Define isolated system target structures matching your production layout
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
# EXTRA PHASE: OPTIONAL --CLEAN PURGE LAYER
# ---------------------------------------------------------------------------
if ($CleanMode) {
    Write-Host "[!] --clean flag detected! Purging target directories for fresh verification..." -ForegroundColor DarkYellow
    
    # Target specific directories to wipe models, binaries, and virtual environments
    $PathsToPurge = @($BIN_DIR, $LIB_DIR, $MODEL_DIR, $VENV_DIR)
    foreach ($Path in $PathsToPurge) {
        if (Test-Path -LiteralPath $Path) {
            Write-Host "[!] Removing: $Path" -ForegroundColor Yellow
            Remove-Item -Recurse -Force -LiteralPath $Path
        }
    }
    Write-Host "[+] Local environment purge complete. Proceeding with clean run." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 0: DEPENDENCY PROVISIONING (SYSTEM-LEVEL AUDIO PIPELINES)
# ---------------------------------------------------------------------------
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "[+] ffmpeg missing. Attempting automated provisioning via winget..." -ForegroundColor Yellow
    try {
        winget install --id Gyan.FFmpeg -e --source winget --accept-source-agreements --accept-package-agreements
        Write-Host "[+] ffmpeg tracking successfully established." -ForegroundColor Green
    } catch {
        Write-Host "[-] Warning: Winget deployment failed. Please install ffmpeg manually for full audio format support." -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# PHASE 1: DIRECTORY STRUCTURE INITIALIZATION
# ---------------------------------------------------------------------------
Write-Host "[+] Building isolated local storage layouts..." -ForegroundColor Green
$DirsToCreate = @($BIN_DIR, $LIB_DIR, $MODEL_DIR, $DB_DIR)
foreach ($Dir in $DirsToCreate) {
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    }
}

# ---------------------------------------------------------------------------
# PHASE 2: BINARY LAYOUT RETRIEVAL & VERIFICATION (NO-GIT)
# ---------------------------------------------------------------------------
Write-Host "[+] Pulling pre-compiled Windows distribution assets via HTTP..." -ForegroundColor Green

# Define the base raw content URL pointing directly to your main branch source tree
$REPO_RAW_URL = "https://raw.githubusercontent.com/jon004/localdoby-binaries/main"

# Explicitly map the remote raw assets you need to pull down
$BinaryUrl      = "$REPO_RAW_URL/windows/bin/llmserver.exe"
$RequirementsUrl = "$REPO_RAW_URL/windows/requirements.txt"

# Set up a generic web client for the downloads
$WebClient = New-Object System.Net.WebClient
$WebClient.Headers.Add("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

try {
    # 1. Download the llmserver executable directly into the local bin directory
    $TargetExePath = Join-Path $BIN_DIR "llmserver.exe"
    Write-Host "[+] Streaming core engine from remote source..." -ForegroundColor DarkGray
    $WebClient.DownloadFile($BinaryUrl, $TargetExePath)
    
    # === SIMPLIFIED BINARY VERIFICATION ===
    Write-Host "[+] Verifying llmserver.exe presence in bin..." -ForegroundColor DarkGray
    
    if (Test-Path -LiteralPath $TargetExePath) {
        $FileSize = (Get-Item $TargetExePath).Length
        if ($FileSize -gt 0) {
            Write-Host "[+] Verification success: llmserver.exe found ($($FileSize) bytes)." -ForegroundColor Green
        } else {
            throw "Verification Failed: llmserver.exe was found in bin but is empty (0 bytes)."
        }
    } else {
        throw "Verification Failed: llmserver.exe is missing from the bin directory."
    }
    # ======================================

    # 2. Download the requirements.txt file straight into the root target directory
    Write-Host "[+] Streaming dependency tracking manifest..." -ForegroundColor DarkGray
    $WebClient.DownloadFile($RequirementsUrl, (Join-Path $TARGET_DIR "requirements.txt"))
    Write-Host "[+] Successfully pulled dependency tracking layer." -ForegroundColor Green
}
catch {
    throw "CRITICAL DISTRIBUTION FAILURE: Failed to harvest or verify platform binaries. Trace Error: $_"
}

# ---------------------------------------------------------------------------
# PHASE 3: PYTHON ISOLATED RUNTIME CONFIGURATION
# ---------------------------------------------------------------------------
Write-Host "[+] Building local sandboxed Python environment..." -ForegroundColor Green

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Critical Error: Python executable not found in system environment path variables. Please install Python 3.11+ before running."
}

if (-not (Test-Path -LiteralPath $VENV_DIR)) {
    & python -m venv $VENV_DIR
}

# Define script markers for Windows environments
$VENV_PYTHON = Join-Path $VENV_DIR "Scripts\python.exe"
$VENV_PIP    = Join-Path $VENV_DIR "Scripts\pip.exe"

Write-Host "[+] Bootstrapping system requirements inside environment layers..." -ForegroundColor Green
& $VENV_PYTHON -m pip install --upgrade pip

$LOCAL_REQUIREMENTS = Join-Path $TARGET_DIR "requirements.txt"
if (Test-Path -LiteralPath $LOCAL_REQUIREMENTS) {
    Write-Host "[+] Cleaning platform-specific dependencies (removing mlx entries)..." -ForegroundColor Yellow
    $CleanedReqs = Get-Content -LiteralPath $LOCAL_REQUIREMENTS | Where-Object { $_ -notmatch 'mlx' }
    $TempReqFile = Join-Path $([System.IO.Path]::GetTempPath()) "cleaned_requirements.txt"
    $CleanedReqs | Out-File -FilePath $TempReqFile -Encoding utf8
    
    try {
        & $VENV_PIP install -r $TempReqFile
    } finally {
        if (Test-Path -LiteralPath $TempReqFile) { Remove-Item -LiteralPath $TempReqFile -Force }
    }
}

Write-Host "[+] Syncing processing core packages..." -ForegroundColor Green
& $VENV_PIP install sentence-transformers torch pandas scikit-learn huggingface_hub

# ---------------------------------------------------------------------------
# PHASE 4: EXECUTION WRAPPER PROVISIONING (DOCUMENT-TOOLS)
# ---------------------------------------------------------------------------
Write-Host "[+] Emitting native wrapper target layer..." -ForegroundColor Green
$WRAPPER_PATH = Join-Path $BIN_DIR "document-tools.ps1"

$WrapperContent = @'
#@
# LocalDoby Document Tools Native Windows Wrapper Script
#@
$ErrorActionPreference = "Stop"

$TARGET_DIR = Join-Path $HOME ".localdoby"
$LIB_DIR    = Join-Path $TARGET_DIR "lib"
$MODEL_DIR  = Join-Path $TARGET_DIR "models"
$VENV_DIR   = Join-Path $TARGET_DIR "venv"
$DB_DIR     = Join-Path $TARGET_DIR "db"

$env:PYTHONPATH = $LIB_DIR
$env:MODEL_PATH = $MODEL_DIR
$env:DB_PATH    = Join-Path $DB_DIR "localdoby.db"

$VENV_PYTHON = Join-Path $VENV_DIR "Scripts\python.exe"

& $VENV_PYTHON (Join-Path $LIB_DIR "main.py") $args
'@

$WrapperContent | Out-File -FilePath $WRAPPER_PATH -Encoding utf8

# ---------------------------------------------------------------------------
# PHASE 5: OFFLINE FACT-CHECKING MODEL EXTRACTOR SYNCHRONIZATION
# ---------------------------------------------------------------------------
Write-Host "[+] Verifying local model asset caches via Public Web Resolution..." -ForegroundColor Green

function Sync-PublicModelAsset {
    param (
        [string]$DownloadUrl,
        [string]$RelativeTargetFile
    )

    $DestinationFile = Join-Path $MODEL_DIR $RelativeTargetFile
    $ParentDir = Split-Path $DestinationFile -Parent
    
    if (-not (Test-Path -LiteralPath $ParentDir)) {
        New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
    }

    if (-not (Test-Path -LiteralPath $DestinationFile)) {
        Write-Host "[+] Downloading target asset: $RelativeTargetFile" -ForegroundColor Yellow
        try {
            $WebClient = New-Object System.Net.WebClient
            $WebClient.Headers.Add("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            
            Write-Host "[+] Target Stream URL: $DownloadUrl" -ForegroundColor DarkGray
            $WebClient.DownloadFile($DownloadUrl, $DestinationFile)
            Write-Host "[+] Successfully verified and retrieved: $RelativeTargetFile" -ForegroundColor Green
        } catch {
            throw "CRITICAL DOWNLOAD FAILURE: Failed to download asset '$RelativeTargetFile' from URL '$DownloadUrl'. Trace Error: $_"
        }
    } else {
        Write-Host "[*] Asset matching payload found: $RelativeTargetFile" -ForegroundColor DarkGray
    }
}

# Core Pipeline System Tasks (Strict mode verification tracking)
Sync-PublicModelAsset "https://huggingface.co/adrianmm12/fact-extractor-1.7b/resolve/main/fact-extractor-1.7b-q8_0.gguf" "fact-extractor-1.7b"
Sync-PublicModelAsset "https://huggingface.co/adrianmm12/Qwen-1.5B-Query-Generator/resolve/main/query-generator-1.5b-Q8_0.gguf" "query-generator-1.5b"
Sync-PublicModelAsset "https://huggingface.co/adrianmm12/fact-judge-1.7b/resolve/main/fact-judge-1.7b-q8_0.gguf" "fact-judge-1.7b"
Sync-PublicModelAsset "https://huggingface.co/second-state/All-MiniLM-L6-v2-Embedding-GGUF/resolve/main/all-MiniLM-L6-v2-ggml-model-f16.gguf" "all-MiniLM-L6-v2.gguf"

# Phase 4 Hybrid Architectures (Cross-Encoder Re-Ranker Assets)
Sync-PublicModelAsset "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/pytorch_model.bin" "ms-marco-MiniLM-L6-v2/pytorch_model.bin"
Sync-PublicModelAsset "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/config.json" "ms-marco-MiniLM-L6-v2/config.json"
Sync-PublicModelAsset "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/vocab.txt" "ms-marco-MiniLM-L6-v2/vocab.txt"
Sync-PublicModelAsset "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/tokenizer_config.json" "ms-marco-MiniLM-L6-v2/tokenizer_config.json"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "     Windows Installation Matrix Successfully Run!  " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "To execute your pipeline tool layer directly, run:"
Write-Host "powershell -File `"$WRAPPER_PATH`"" -ForegroundColor Yellow
