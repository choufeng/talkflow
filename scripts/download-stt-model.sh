#!/bin/bash
# 下载 SenseVoiceSmall ONNX 模型文件到 Resources/sensevoice/
# 来源：haixuantao/SenseVoiceSmall-onnx (HuggingFace)
set -e

MODEL_DIR="$(dirname "$0")/../TalkFlow/Resources/sensevoice"
mkdir -p "$MODEL_DIR"

BASE="https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/main"

FILES=(
    "model_quant.onnx:21dc965f689a78d1604717bf561e40d5a236087c85a95584567835750549e822"
    "am.mvn:29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5"
    "chn_jpn_yue_eng_ko_spectok.bpe.model:a2594fc1474e78973149cba8cd1f603ebed8c39c7decb470631f66e70ce58e97"
    "tokens.json:aa87f86064c3730d799ddf7af3c04659151102cba548bce325cf06ba4da4e6a8"
    "config.yaml:f71e239ba36705564b5bf2d2ffd07eece07b8e3f2bbf6d2c99d8df856339ac19"
)

for entry in "${FILES[@]}"; do
    file="${entry%%:*}"
    hash="${entry##*:}"
    echo "Downloading $file..."
    curl -sL "$BASE/$file" -o "$MODEL_DIR/$file"
    actual=$(shasum -a 256 "$MODEL_DIR/$file" | cut -d' ' -f1)
    if [ "$actual" != "$hash" ]; then
        echo "❌ Hash mismatch for $file"
        exit 1
    fi
done

echo "✅ All model files downloaded to $MODEL_DIR"
