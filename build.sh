#!/bin/bash
# 图片缩略图工具 —— 手工构建脚本（无需 Xcode）
# 用法：./build.sh [--install]
#   --install  构建后安装到 /Applications 并注册 Finder 扩展

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
APP_NAME="图片缩略图工具"
APP_BUNDLE="$BUILD/$APP_NAME.app"
APP_EXEC="ImageThumbMaker"
SYNC_EXEC="ImageThumbMakerSync"
DEPLOY_TARGET="13.0"

SDK="$(xcrun --show-sdk-path)"
# 注意：/usr/bin/clang 在本机会被 swift driver 劫持，必须用 CLT 内的真实 clang
CLANG="/Library/Developer/CommandLineTools/usr/bin/clang"
TARGET="arm64-apple-macosx${DEPLOY_TARGET}"

COMMON_FLAGS=(
  -isysroot "$SDK"
  -target "$TARGET"
  -mmacosx-version-min="$DEPLOY_TARGET"
  -fobjc-arc
  -Wall
  -Wno-unused-variable
)

SHARED_SRC=(
  "$ROOT/Sources/Shared/ITMThumbConfig.m"
  "$ROOT/Sources/Shared/ITMImageSupport.m"
  "$ROOT/Sources/Shared/ITMThumbnailGenerator.m"
)

echo "==> 清理构建目录"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# ---------------------------------------------------------------------------
# 1. 编译 Finder Sync 扩展
# ---------------------------------------------------------------------------
echo "==> 编译 Finder Sync 扩展"
mkdir -p "$BUILD/$SYNC_EXEC"

"$CLANG" "${COMMON_FLAGS[@]}" \
  -bundle \
  -framework Foundation \
  -framework AppKit \
  -framework FinderSync \
  -framework ImageIO \
  -framework CoreGraphics \
  -framework UniformTypeIdentifiers \
  -I"$ROOT/Sources/Shared" \
  -I"$ROOT/Sources/Extension" \
  -o "$BUILD/$SYNC_EXEC/$SYNC_EXEC" \
  "$ROOT/Sources/Extension/FinderSyncHandler.m" \
  "${SHARED_SRC[@]}"

# 组装 .appex 结构
mkdir -p "$BUILD/$SYNC_EXEC/Contents/Resources"
mv "$BUILD/$SYNC_EXEC/$SYNC_EXEC" "$BUILD/$SYNC_EXEC/Contents/$SYNC_EXEC"

# ObjC 的 NSExtensionPrincipalClass 直接写类名，不带模块前缀。
# Swift 才需要 $(PRODUCT_MODULE_NAME).ClassName 形式。
cp "$ROOT/Resources/Sync-Info.plist" "$BUILD/$SYNC_EXEC/Contents/Info.plist"

# ---------------------------------------------------------------------------
# 2. 编译宿主 App
# ---------------------------------------------------------------------------
echo "==> 编译宿主 App"
mkdir -p "$BUILD/$APP_EXEC"

"$CLANG" "${COMMON_FLAGS[@]}" \
  -framework Foundation \
  -framework AppKit \
  -framework FinderSync \
  -framework ImageIO \
  -framework CoreGraphics \
  -framework UniformTypeIdentifiers \
  -I"$ROOT/Sources/Shared" \
  -o "$BUILD/$APP_EXEC/$APP_EXEC" \
  "$ROOT/Sources/App/main.m" \
  "${SHARED_SRC[@]}"

# ---------------------------------------------------------------------------
# 3. 编译命令行版生成器（Services 工作流后端）
# ---------------------------------------------------------------------------
echo "==> 编译命令行生成器"
"$CLANG" "${COMMON_FLAGS[@]}" \
  -framework Foundation \
  -framework AppKit \
  -framework ImageIO \
  -framework CoreGraphics \
  -framework UniformTypeIdentifiers \
  -I"$ROOT/Sources/Shared" \
  -o "$BUILD/thumbgen" \
  "$ROOT/Sources/CLI/thumbgen.m" \
  "${SHARED_SRC[@]}"

chmod +x "$ROOT/mkthumb.sh"

# ---------------------------------------------------------------------------
# 4. 组装 .app
# ---------------------------------------------------------------------------
echo "==> 组装 .app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/PlugIns"
mkdir -p "$APP_BUNDLE/Contents/Resources"

mv "$BUILD/$APP_EXEC/$APP_EXEC" "$APP_BUNDLE/Contents/MacOS/$APP_EXEC"
cp "$ROOT/Resources/App-Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 应用图标
cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# 扩展嵌入 PlugIns
mv "$BUILD/$SYNC_EXEC" "$APP_BUNDLE/Contents/PlugIns/$SYNC_EXEC.appex"

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# 5. 代码签名（ad-hoc）
# ---------------------------------------------------------------------------
echo "==> 代码签名"
# 重要：必须显式指向 appex 内部的可执行文件签，否则 entitlement 不会写入
SYNC_BIN="$APP_BUNDLE/Contents/PlugIns/$SYNC_EXEC.appex/Contents/$SYNC_EXEC"
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/Resources/Sync.entitlements" \
  "$SYNC_BIN" 2>&1 | sed 's/^/    /'

codesign --force --sign - --timestamp=none \
  "$APP_BUNDLE/Contents/PlugIns/$SYNC_EXEC.appex" 2>&1 | sed 's/^/    /'

codesign --force --sign - --timestamp=none \
  "$APP_BUNDLE" 2>&1 | sed 's/^/    /'

echo "==> 验证签名"
if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
  echo "    签名有效"
else
  echo "    ⚠️  签名校验未通过（ad-hoc 签名下的常见提示）"
fi

# ---------------------------------------------------------------------------
# 6. 安装与注册
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/$APP_NAME.app"

  echo "==> 安装到 $DEST"
  # 先注销旧版本，避免 pluginkit 里残留失效记录
  if [[ -d "$DEST" ]]; then
    pluginkit -r "$DEST/Contents/PlugIns/$SYNC_EXEC.appex" 2>/dev/null || true
    rm -rf "$DEST"
  fi
  cp -R "$APP_BUNDLE" "$DEST"

  echo "==> 注册 Finder 扩展"
  pluginkit -a "$DEST/Contents/PlugIns/$SYNC_EXEC.appex"

  # 让 Finder 重新加载扩展
  killall Finder 2>/dev/null || true

  echo ""
  echo "✅ 安装完成：$DEST"
  echo ""
  echo "首次使用需在「系统设置 → 通用 → 登录项与扩展 → 扩展」中"
  echo "打开「图片缩略图工具」的开关。"
  echo ""
  echo "打开设置面板： open \"$DEST\" --args --settings"
else
  echo ""
  echo "✅ 构建完成：$APP_BUNDLE"
  echo "   安装请执行： ./build.sh --install"
fi
