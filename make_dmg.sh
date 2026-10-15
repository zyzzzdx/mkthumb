#!/bin/bash
# 打包 DMG：包含应用、使用说明、许可说明
# 用法：./make_dmg.sh [版本号]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-1.2.0}"
APP_NAME="图片缩略图工具"
APP_SRC="/Applications/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD="$ROOT/build"
STAGE="$BUILD/dmg-stage"

# ---------------------------------------------------------------------------
# 前置检查
# ---------------------------------------------------------------------------
if [ ! -d "$APP_SRC" ]; then
    echo "❌ 未找到 $APP_SRC，请先执行 ./build.sh --install"
    exit 1
fi

echo "==> 清理旧产物"
rm -rf "$STAGE" "$BUILD/$DMG_NAME"
mkdir -p "$STAGE"

# ---------------------------------------------------------------------------
# 准备暂存目录
# ---------------------------------------------------------------------------
echo "==> 拷贝应用"
cp -R "$APP_SRC" "$STAGE/"

# 去掉 appex（无证书无法启用，带去只会让用户困惑）
rm -rf "$STAGE/$APP_NAME.app/Contents/PlugIns"

echo "==> 生成说明文档"
cat > "$STAGE/使用说明.txt" << 'DOC'
图片缩略图工具 v1.2.0
========================

一个本地运行的图片缩略图生成工具。
默认输出 JPG · 品质低 · 长边 ≤800px，生成 *_thumb.jpg 到原目录。


三种用法
--------

1. 拖放（推荐）
   打开应用，把图片或整个文件夹拖进窗口即可批量生成。
   建议把应用拖进 Dock，之后直接拖图到 Dock 图标。

2. 命令行
   mkthumb ~/Pictures/photo.png
   mkthumb a.png b.png c.png                批量
   ITM_FORMAT=png mkthumb photo.png         输出 PNG
   ITM_QUALITY=low mkthumb photo.png        品质（low/medium/high）
   ITM_MAXPIXEL=1600 mkthumb photo.png      长边上限
   ITM_SUFFIX=_small mkthumb photo.png      自定义后缀

3. 窗口内按钮
   点「选择图片…」通过文件选择器挑选。


质量档位
--------
窗口中的下拉框可切换长边上限，下次生成生效：

    高    ≤1024px
    中    ≤800px
    低    ≤400px
    很低  ≤200px

JPG 保存品质固定为低，与尺寸档位无关。
始终按原始比例缩放，小图不会被放大。


支持格式
--------
jpg / jpeg / png / gif / bmp / tif / tiff / heic / heif / webp / avif

其他特性：
- 透明图片转 JPG 自动铺白底（不会出现黑底）
- 自动按 EXIF 方向旋转
- 单张失败不影响同批其它文件
- 重复执行覆盖同名文件，不堆积


快捷键
------
Cmd+W   关闭窗口并退出
Cmd+Q   退出
Cmd+C / Cmd+V 等组合键不受影响


安装
----
把「图片缩略图工具」拖到「应用程序」文件夹即可。

首次打开如被系统拦截（提示"无法验证开发者"），请：
    系统设置 → 隐私与安全性 → 安全性 → 点「仍要打开」
或右键应用图标 → 打开。


命令行工具的安装
----------------
命令行（mkthumb）需要单独配置 PATH，在终端执行：

    mkdir -p ~/.local/bin
    cp -R 图片缩略图工具.app/Contents/Resources/bin/. ~/.local/bin/
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    source ~/.zshrc

之后即可使用 mkthumb 命令。


卸载
----
删除应用，并执行：

    rm -f ~/.local/bin/mkthumb ~/.local/bin/thumbgen
    rm -f ~/Library/Application\ Support/ImageThumbMaker/config.json
    rm -f ~/Library/Logs/ImageThumbMaker.log


隐私
----
本工具完全离线运行，不联网、不上传、不收集任何数据。
所有处理均在本机完成。


开源
----
源码位于 ImageThumbMaker/ 目录，可自行构建：

    ./build.sh --install
    ./test.sh
DOC

cat > "$STAGE/许可声明.txt" << 'DOC'
图片缩略图工具 — 许可声明
========================

本软件按「现状」提供，不附带任何明示或暗示的担保，
包括但不限于对适销性、特定用途适用性的担保。

你可以自由使用、复制和分发本软件及其源代码，
包括用于商业目的，无需支付费用或取得授权。

作者不对因使用本软件而产生的任何直接或间接损失承担责任。

缩略图生成基于 Apple ImageIO 框架实现。
DOC

# 命令行工具一并打包（可选安装）
echo "==> 打包命令行工具"
mkdir -p "$STAGE/.commandline"
cp "$HOME/.local/bin/thumbgen" "$STAGE/.commandline/" 2>/dev/null || true
cp "$ROOT/mkthumb.sh" "$STAGE/.commandline/mkthumb" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 生成 DMG
# ---------------------------------------------------------------------------
echo "==> 生成 DMG"
DMG_TMP="$BUILD/dmg-tmp.dmg"
# hdiutil 在 macOS 27 被标记 deprecated 但功能完整；diskutil image 的选项
# 与旧写法不兼容，强行改写风险更高，因此沿用 hdiutil 并屏蔽弃用告警
hdiutil create -volname "$APP_NAME $VERSION" \
    -fs HFS+ \
    -srcfolder "$STAGE" \
    -ov -format UDRW \
    "$DMG_TMP" 2>&1 | grep -v "deprecated" || true

# 挂载后设置窗口布局（背景、图标位置、窗口大小）
echo "==> 设置 DMG 窗口布局"
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" \
    | grep -o '/Volumes/.*' | head -1)

if [ -n "$MOUNT_DIR" ]; then
    # 背景图
    if [ -f "$ROOT/Resources/dmg-background.png" ]; then
        mkdir -p "$MOUNT_DIR/.background"
        cp "$ROOT/Resources/dmg-background.png" "$MOUNT_DIR/.background/"
    fi

    osascript << OSA || true
tell application "Finder"
    tell disk "$(basename "$MOUNT_DIR")"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 560}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 120
        set background picture of theViewOptions to file ".background:dmg-background.png"
        set position of item "$APP_NAME.app" of container window to {160, 200}
        set position of item "使用说明.txt" of container window to {460, 130}
        set position of item "许可声明.txt" of container window to {460, 280}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
OSA

    sync
    hdiutil detach "$MOUNT_DIR" >/dev/null
fi

# 压缩为最终 DMG
echo "==> 压缩"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 \
    -o "$BUILD/$DMG_NAME" >/dev/null
rm -f "$DMG_TMP"
rm -rf "$STAGE"

SIZE=$(du -h "$BUILD/$DMG_NAME" 2>/dev/null | cut -f1)
if [ -z "$SIZE" ]; then SIZE="unknown"; fi
echo ""
echo "✅ DMG 已生成：$BUILD/$DMG_NAME （$SIZE）"
