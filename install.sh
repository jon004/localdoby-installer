#!/bin/bash
set -e

# Configuration
TARGET_DIR="$HOME/.localdoby"
BIN_DIR="$TARGET_DIR/bin"
LIB_DIR="$TARGET_DIR/lib"
MODEL_DIR="$TARGET_DIR/models"
VENV_DIR="$TARGET_DIR/venv"

echo "--- Installing LocalDoby ---"

# 1. Create directory structure
mkdir -p "$BIN_DIR" "$LIB_DIR" "$MODEL_DIR"

# 2. Fetch Binaries and Config
TEMP_DIR=$(mktemp -d)
git clone https://github.com/jon004/localdoby-binaries.git "$TEMP_DIR"

cp "$TEMP_DIR/bin/llmserver" "$BIN_DIR/"
cp -r "$TEMP_DIR/lib/"* "$LIB_DIR/"
cp "$TEMP_DIR/requirements.txt" "$TARGET_DIR/"
chmod +x "$BIN_DIR/llmserver"

# 3. Setup Python Virtual Environment (Using Pinned Requirements)
echo "Setting up Python environment..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$TARGET_DIR/requirements.txt"

# 4. Generate CLI wrapper
cat << EOF > "$BIN_DIR/document-tools"
#!/bin/bash
source "$VENV_DIR/bin/activate"
export PYTHONPATH="$LIB_DIR"
exec python3 -c "import main; main.main()" "\$@"
EOF
chmod +x "$BIN_DIR/document-tools"

# 5. Download Models
check_and_download() {
    local DEST="$MODEL_DIR/$2"
    if [[ ! -f "$DEST" ]]; then
        echo "Downloading $2..."
        curl -L "$1" -o "$DEST"
    fi
}
check_and_download "https://huggingface.co/TheBloke/dolphin-2.2.1-mistral-7B-GGUF/resolve/main/dolphin-2.2.1-mistral-7b.Q4_K_M.gguf" "7b-chatml-model.gguf"
check_and_download "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf" "small-qwen2-model.gguf"
check_and_download "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf" "embed-model.gguf"

rm -rf "$TEMP_DIR"
echo "Installation Successful!"
