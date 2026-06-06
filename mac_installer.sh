#!/bin/bash
set -e

TARGET_DIR="$HOME/.localdoby"
BIN_DIR="$TARGET_DIR/bin"
LIB_DIR="$TARGET_DIR/lib"
MODEL_DIR="$TARGET_DIR/models"
VENV_DIR="$TARGET_DIR/venv"
DB_DIR="$TARGET_DIR/db" # ADDED: Phase 5/Database alignment[cite: 19]

echo "--- Installing LocalDoby ---"

# 0. Install system dependencies
if command -v brew &> /dev/null; then
    echo "Installing ffmpeg for audio format support..."
    brew install ffmpeg || echo "Warning: ffmpeg installation failed. Audio format support may be limited."
else
    echo "Warning: Homebrew not found. Please install ffmpeg manually for audio format support."
fi

# 1. Create directory structure
mkdir -p "$BIN_DIR" "$LIB_DIR" "$MODEL_DIR" "$DB_DIR"

# 2. Fetch Binaries and Config
TEMP_DIR=$(mktemp -d)
git clone https://github.com/jon004/localdoby-binaries.git "$TEMP_DIR"
cp "$TEMP_DIR/bin/llmserver" "$BIN_DIR/"
cp -r "$TEMP_DIR/lib/"* "$LIB_DIR/"
cp "$TEMP_DIR/requirements.txt" "$TARGET_DIR/"
chmod +x "$BIN_DIR/llmserver"

# 2. Python Setup[cite: 22]
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$TARGET_DIR/requirements.txt"
# Ensure specific hybrid retrieval dependencies are present[cite: 19]
pip install sentence-transformers torch pandas scikit-learn 

# 3. CLI Wrapper[cite: 19, 22]
cat << EOF > "$BIN_DIR/document-tools"
#!/bin/bash
source "$VENV_DIR/bin/activate"
export PYTHONPATH="$LIB_DIR"
export MODEL_PATH="$MODEL_DIR"
export DB_PATH="$DB_DIR/localdoby.db"
exec python3 "$LIB_DIR/main.py" "\$@"
EOF
chmod +x "$BIN_DIR/document-tools"

# 4. Phase-Specific Model Downloads[cite: 1, 19]
check_and_download() {
    local DEST="$MODEL_DIR/$2"
    if [[ ! -f "$DEST" ]]; then
        echo "Downloading $2..."
        curl -L "$1" -o "$DEST"
    fi
}

# Core Pipeline Models[cite: 2]
check_and_download "https://huggingface.co/adrianmm12/fact-extractor-1.7b/resolve/main/fact-extractor-1.7b.Q4_K_M.gguf" "fact-extractor-1.7b"
check_and_download "https://huggingface.co/adrianmm12/Qwen-1.5B-Query-Generator/resolve/main/query-gen-1.5b.Q4_K_M.gguf" "query-generator-1.5b"
check_and_download "https://huggingface.co/adrianmm12/fact-judge-1.7b/resolve/main/fact-judge-1.7b.Q4_K_M.gguf" "fact-judge-1.7b"
check_and_download "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/ggml-model-f16.gguf" "all-MiniLM-L6-v2.gguf"

# Phase 4: Full Re-ranker Assets[cite: 9, 19]
R_DIR="$MODEL_DIR/ms-marco-MiniLM-L6-v2"
mkdir -p "$R_DIR"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/pytorch_model.bin" "ms-marco-MiniLM-L6-v2/pytorch_model.bin"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/config.json" "ms-marco-MiniLM-L6-v2/config.json"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/vocab.txt" "ms-marco-MiniLM-L6-v2/vocab.txt"
check_and_download "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2/resolve/main/tokenizer_config.json" "ms-marco-MiniLM-L6-v2/tokenizer_config.json"

rm -rf "$TEMP_DIR"
echo "Installation Complete."
