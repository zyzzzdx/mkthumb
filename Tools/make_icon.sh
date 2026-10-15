#!/bin/bash
# 重新生成应用图标 AppIcon.icns
# 用法：./Tools/make_icon.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLANG="/Library/Developer/CommandLineTools/usr/bin/clang"
SRC="$ROOT/Tools/make_app_icon.m"
ICONSET="$ROOT/Resources/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"
BIN=$(mktemp -t itmicon)

trap 'rm -f "$BIN"' EXIT

echo "==> 编译图标绘制程序"
"$CLANG" -isysroot "$(xcrun --show-sdk-path)" -target arm64-apple-macosx13.0 \
  -fobjc-arc -framework Cocoa -o "$BIN" "$SRC"

echo "==> 生成各尺寸 PNG"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in "16:16" "32:16@2x" "32:32" "128:32@2x" "128:128" "256:128@2x" \
            "256:256" "512:256@2x" "512:512" "1024:512@2x"; do
  size="${spec%%:*}"
  name="${spec##*:}"
  "$BIN" "$ICONSET/icon_${name}.png" "$size"
done

echo "==> 合成 icns"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✅ $OUT"
