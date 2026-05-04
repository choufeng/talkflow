#!/bin/bash
# 将 Homebrew 依赖 dylib 打包进 .app，修正 install name，ad-hoc 签名
set -euo pipefail

APP="$1"
FRAMEWORKS="$APP/Contents/Frameworks"
EXEC="$APP/Contents/MacOS/TalkFlow"

echo "📦 Bundling dylibs into $APP..."

rm -rf "$FRAMEWORKS"
mkdir -p "$FRAMEWORKS"

# ── 递归收集所有 /opt/homebrew 依赖（用临时文件去重） ──
TMP=$(mktemp)
TO_PROCESS=("$EXEC")

while [ ${#TO_PROCESS[@]} -gt 0 ]; do
  file="${TO_PROCESS[0]}"
  TO_PROCESS=("${TO_PROCESS[@]:1}")

  otool -L "$file" 2>/dev/null | awk '/^\t/ {print $1}' | while read -r dep; do
    [[ "$dep" == /opt/homebrew/* ]] || continue
    echo "$dep"
  done >> "$TMP"
done

# 去重
COLLECTED=($(sort -u "$TMP" | grep '^/opt/homebrew'))
rm "$TMP"

# 递归：检查新收集到的 dylib 是否还有未发现的依赖
i=0
while [ $i -lt ${#COLLECTED[@]} ]; do
  otool -L "${COLLECTED[$i]}" 2>/dev/null | awk '/^\t/ {print $1}' | while read -r dep; do
    [[ "$dep" == /opt/homebrew/* ]] || continue
    echo "$dep"
  done >> "$TMP"
  i=$((i + 1))
done

# 合并并再次去重
while IFS= read -r dep; do
  COLLECTED+=("$dep")
done < <(sort -u "$TMP" 2>/dev/null || true)
rm -f "$TMP"

COLLECTED=($(printf '%s\n' "${COLLECTED[@]}" | sort -u | grep '^/opt/homebrew'))

echo "  Found ${#COLLECTED[@]} Homebrew dylibs"

# ── 拷贝 + 修改 id + 修正依赖路径 ──
for src in "${COLLECTED[@]}"; do
  name=$(basename "$src")
  dest="$FRAMEWORKS/$name"
  [ -f "$dest" ] && continue  # 已存在则跳过
  cp "$src" "$dest"
  chmod u+w "$dest"

  # 修改 dylib 自身的 install name
  install_name_tool -id "@rpath/$name" "$dest" 2>/dev/null || true

  # 修改该 dylib 对其它 Homebrew dylib 的引用
  otool -L "$dest" 2>/dev/null | awk '/^\t/ {print $1}' | while read -r ref; do
    [[ "$ref" == /opt/homebrew/* ]] || continue
    refname=$(basename "$ref")
    install_name_tool -change "$ref" "@rpath/$refname" "$dest" 2>/dev/null || true
  done
done

# ── 修正可执行文件对 Homebrew dylib 的引用 → @rpath ──
echo "  Fixing executable dylib refs..."
otool -L "$EXEC" 2>/dev/null | awk '/^\t/ {print $1}' | while read -r ref; do
  [[ "$ref" == /opt/homebrew/* ]] || continue
  refname=$(basename "$ref")
  install_name_tool -change "$ref" "@rpath/$refname" "$EXEC" 2>/dev/null || true
done

# ── Ad-hoc 签名所有 dylib ──
echo "🔏 Signing dylibs..."
for dylib in "$FRAMEWORKS"/*.dylib; do
  [ -f "$dylib" ] || continue
  codesign --force --sign - "$dylib" 2>/dev/null
done

# ── Ad-hoc 签名整个 .app ──
echo "🔏 Signing app..."
codesign --force --deep --sign - "$APP"

echo "✅ Done bundling"
