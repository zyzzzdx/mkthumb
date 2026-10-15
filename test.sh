#!/bin/bash
# 核心逻辑自测：不依赖 Finder，直接验证缩略图生成正确性

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK="$(xcrun --show-sdk-path)"
CLANG="/Library/Developer/CommandLineTools/usr/bin/clang"
TARGET="arm64-apple-macosx13.0"
OUT="$ROOT/build/selftest"

mkdir -p "$OUT"
rm -rf /tmp/itmsel

echo "==> 编译自测程序"
"$CLANG" \
  -isysroot "$SDK" \
  -target "$TARGET" \
  -fobjc-arc \
  -framework Foundation \
  -framework AppKit \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -I "$ROOT/Sources/Shared" \
  -o "$OUT/selftest" \
  "$ROOT/Tests/selftest.m" \
  "$ROOT/Sources/Shared/ITMThumbConfig.m" \
  "$ROOT/Sources/Shared/ITMImageSupport.m" \
  "$ROOT/Sources/Shared/ITMThumbnailGenerator.m"

echo "==> 运行自测"
# ITMSELFTEST 让配置读写指向独立目录，不影响真实设置
ITMSELFTEST=1 "$OUT/selftest"
STATUS=$?

# 清理测试产生的临时文件
rm -rf /tmp/itmsel
rm -rf ~/Library/Application\ Support/ImageThumbMaker-Selftest
rm -f ~/Library/Logs/ImageThumbMaker-Selftest.log

exit $STATUS
