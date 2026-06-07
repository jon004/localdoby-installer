#!/bin/bash
set -e

# --- Configuration & Paths ---
TARGET_DIR="$HOME/.localdoby"
BIN_DIR="$TARGET_DIR/bin"
LIB_DIR="$TARGET_DIR/lib"
MODEL_DIR="$TARGET_DIR/models"
VENV_DIR="$TARGET_DIR/venv"
DB_DIR="$TARGET_DIR/db"

# --- Hardened Environment Constants ---
REQUIRED_PYTHON_VERSION="3.12"
PYTHON_EXE="/opt/homebrew/bin/python${REQUIRED_PYTHON_VERSION}"
EXPAT_LIB_PATH="/opt/homebrew/opt/expat/lib"

echo "--- Installing LocalDoby (Hardened) ---"

# 0. System Dependencies
if command -v brew &> /dev/null; then
    echo "Installing ffmpeg for audio support..."
    brew install ffmpeg || echo "Warning: ffmpeg installation failed."
else
    echo "Warning: Homebrew not found. Please install ffmpeg manually for audio support."
fi

# 1. Enforce Correct Python Version
if [[ ! -f "$PYTHON_EXE" ]]; then
    echo "Python $REQUIRED_PYTHON_VERSION not found at $PYTHON_EXE. Installing via Homebrew..."
    brew install "python@${REQUIRED_PYTHON_VERSION}" || { echo "Python install failed"; exit 1; }
fi

# 2. Directory Structure
mkdir -p "$BIN_DIR" "$LIB_DIR" "$MODEL_DIR" "$DB_DIR"

# 3. Fetch Binaries and Config
TEMP_DIR=$(mktemp -d)
git clone https://github.com/jon004/localdoby-binaries.git "$TEMP_DIR"

# Updated paths to reflect the 'mac/' subdirectory structure
cp "$TEMP_DIR/mac/bin/llmserver" "$BIN_DIR/"
cp -r "$TEMP_DIR/mac/lib/"* "$LIB_DIR/"
cp "$TEMP_DIR/mac/requirements.txt" "$TARGET_DIR/"

chmod +x "$BIN_DIR/llmserver"
rm -rf "$TEMP_DIR"

# 4. Hardened Python Setup
echo "Creating hardened virtual environment..."
rm -rf "$VENV_DIR"
# Use specific python3.12 binary to create venv
"$PYTHON_EXE" -m venv --without-pip "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Bootstrap pip using hardened linker path to prevent ImportError
export DYLD_LIBRARY_PATH="$EXPAT_LIB_PATH"
curl -sS https://bootstrap.pypa.io/get-pip.py | python3

# Install requirements
pip install --upgrade pip
pip install -r "$TARGET_DIR/requirements.txt"

# 5. CLI Wrapper (with persistent path hardening)
cat << EOF > "$BIN_DIR/document-tools"
#!/bin/bash
export DYLD_LIBRARY_PATH="$EXPAT_LIB_PATH"
source "$VENV_DIR/bin/activate"
export PYTHONPATH="$LIB_DIR"
export MODEL_PATH="$MODEL_DIR"
export DB_PATH="$DB_DIR/localdoby.db"
exec python3 "$LIB_DIR/main.py" "\$@"
EOF
chmod +x "$BIN_DIR/document-tools"

# 6. Model Downloads
check_and_download() {
    local DEST="$MODEL_DIR/$2"
    if [[ ! -f "$DEST" ]]; then
        echo "Downloading $2..."
        curl -L "$1" -o "$DEST"
    fi
}

# Core Pipeline Models
check_and_download "https://huggingface.co/adrianmm12/fact-extractor-1.7b/resolve/main/fact-extractor-1.7b.Q4_K_M.gguf" "fact-extractor-1.7b"
check_and_download "https://huggingface.co/adrianmm12/Qwen-1.5B-Query-Generator/resolve/main/query-gen-1.5b.Q4_K_M.gguf" "query-generator-1.5b"
check_and_download "https://huggingface.co/adrianmm12/fact-judge-1.7b/resolve/main/fact-judge-1.7b.Q4_K_M.gguf" "fact-judge-1.7b"
check_and_download "https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.Q4_K_M.gguf" "all-MiniLM-L6-v2.gguf"
check_and_download "https://huggingface.co/cstr/ms-marco-MiniLM-L-6-v2-GGUF/resolve/main/ms-marco-MiniLM-L-6-v2-q4_k.gguf" "ms-marco-MiniLM-L6-v2"

# Full Re-ranker Assets
R_DIR="$MODEL_DIR/ms-marco-MiniLM-L6-v2"
mkdir -p "$R_DIR"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/pytorch_model.bin" "ms-marco-MiniLM-L6-v2/pytorch_model.bin"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/config.json" "ms-marco-MiniLM-L6-v2/config.json"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/vocab.txt" "ms-marco-MiniLM-L6-v2/vocab.txt"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/tokenizer_config.json" "ms-marco-MiniLM-L6-v2/tokenizer_config.json"

echo "Installation Complete."
