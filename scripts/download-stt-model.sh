#!/bin/bash
# 下载 SenseVoiceSmall ONNX 模型文件到 Resources/sensevoice/
# 来源：haixuantao/SenseVoiceSmall-onnx (HuggingFace)
#
# 用法:
#   download-stt-model.sh          # 校验，缺失/哈希不匹配时下载
#   download-stt-model.sh --force  # 强制重新下载全部文件
#   download-stt-model.sh --check  # 仅校验，不下载（退出码 0=完整，1=缺失）
set -e

MODEL_DIR="$(dirname "$0")/../TalkFlow/Resources/sensevoice"
mkdir -p "$MODEL_DIR"

BASE="https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/main"

FILES=(
    "model_quant.onnx:21dc965f689a78d1604717bf561e40d5a236087c85a95584567835750549e822"
    "am.mvn:29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5"
    "chn_jpn_yue_eng_ko_spectok.bpe.model:aa87f86064c3730d799ddf7af3c04659151102cba548bce325cf06ba4da4e6a8"
    "tokens.json:a2594fc1474e78973149cba8cd1f603ebed8c39c7decb470631f66e70ce58e97"
    "config.yaml:f71e239ba36705564b5bf2d2ffd07eece07b8e3f2bbf6d2c99d8df856339ac19"
)

MODE="${1:-}"

declare -a TO_DOWNLOAD

for entry in "${FILES[@]}"; do
    file="${entry%%:*}"
    expected="${entry##*:}"
    path="$MODEL_DIR/$file"

    if [ "$MODE" = "--force" ]; then
        TO_DOWNLOAD+=("$entry")
        continue
    fi

    if [ ! -f "$path" ]; then
        [ "$MODE" != "--check" ] && echo "⚠️  Missing: $file"
        TO_DOWNLOAD+=("$entry")
        continue
    fi

    actual=$(shasum -a 256 "$path" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        [ "$MODE" != "--check" ] && echo "⚠️  Hash mismatch: $file"
        TO_DOWNLOAD+=("$entry")
        continue
    fi

    [ "$MODE" != "--check" ] && echo "✅ $file (valid)"
done

if [ "$MODE" = "--check" ]; then
    if [ ${#TO_DOWNLOAD[@]} -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

if [ ${#TO_DOWNLOAD[@]} -eq 0 ]; then
    echo "✅ All model files present and valid."
    exit 0
fi

for entry in "${TO_DOWNLOAD[@]}"; do
    file="${entry%%:*}"
    expected="${entry##*:}"
    echo "📥 Downloading $file..."
    curl -sL "$BASE/$file" -o "$MODEL_DIR/$file"
    actual=$(shasum -a 256 "$MODEL_DIR/$file" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        echo "❌ Hash mismatch after download: $file"
        exit 1
    fi
    echo "   Done."
done

echo "✅ All model files downloaded to $MODEL_DIR"
