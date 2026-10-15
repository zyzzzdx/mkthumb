#!/bin/bash
# Windows 版构建脚本
#
# 产出两个可执行文件：
#   build/mkthumb.exe     命令行版
#   build/mkthumb-gui.exe 拖放窗口版（置顶 + 拖放 + 4 档质量）
#
# 依赖：MinGW-w64（macOS/Linux 上交叉编译）
#   macOS:  brew install mingw-w64
#   Linux:  apt install gcc-mingw-w64-x86-64

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src"
THIRD="$ROOT/third_party"
BUILD="$ROOT/build"
CXX="${CXX:-g++}"
STD="-std=c++17"

mkdir -p "$BUILD"

echo "==> 检测编译器"

if command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
    CXX="x86_64-w64-mingw32-g++"
    TARGET="windows"
    EXTRA="-static -static-libgcc -static-libstdc++"
    OUT_CLI="$BUILD/mkthumb.exe"
    OUT_GUI="$BUILD/mkthumb-gui.exe"
elif command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    CXX="x86_64-w64-mingw32-gcc"
    TARGET="windows"
    EXTRA="-static -static-libgcc -static-libstdc++"
    OUT_CLI="$BUILD/mkthumb.exe"
    OUT_GUI="$BUILD/mkthumb-gui.exe"
else
    TARGET="native"
    EXTRA=""
    OUT_CLI="$BUILD/mkthumb"
    OUT_GUI="$BUILD/mkthumb-gui"
fi

echo "    编译器: $CXX"
echo "    目标:   $TARGET"

# 清理上次构建的残留（避免 Mach-O 与 PE 混淆）
rm -f "$BUILD/mkthumb" "$BUILD/mkthumb.exe" \
      "$BUILD/mkthumb-gui" "$BUILD/mkthumb-gui.exe"

COMMON_FLAGS=(
    $STD -O2 -Wall -Wextra
    -I"$SRC" -I"$SRC/gui" -I"$THIRD"
    $EXTRA
)

# ---------------------------------------------------------------------------
# 1. 命令行版
# ---------------------------------------------------------------------------
echo "==> 编译命令行版 mkthumb.exe"
"$CXX" "${COMMON_FLAGS[@]}" \
    -o "$OUT_CLI" \
    "$SRC/thumb_config.cpp" \
    "$SRC/thumbnail_generator.cpp" \
    "$SRC/mkthumb.cpp"

# ---------------------------------------------------------------------------
# 2. 拖放窗口版
# ---------------------------------------------------------------------------
if [ "$TARGET" = "windows" ]; then
    echo "==> 编译窗口版 mkthumb-gui.exe"
    # -mwindows：入口改为 WinMain，且不弹出控制台窗口
    # -municode：使用宽字符 API（CreateWindowExW / DragQueryFileW）
    # shell32（拖放 WM_DROPFILES）、comdlg32（文件选择对话框）
    "$CXX" "${COMMON_FLAGS[@]}" -mwindows -municode \
        -lshell32 -lcomdlg32 \
        -o "$OUT_GUI" \
        "$SRC/thumb_config.cpp" \
        "$SRC/thumbnail_generator.cpp" \
        "$SRC/gui/gui_app.cpp" \
        "$SRC/gui/gui_main.cpp"
else
    echo "==> 跳过窗口版（需 MinGW 交叉编译）"
fi

# ---------------------------------------------------------------------------
# 3. 剥离符号
# ---------------------------------------------------------------------------
if [ "$TARGET" = "windows" ] && command -v x86_64-w64-mingw32-strip >/dev/null 2>&1; then
    echo "==> 剥离符号"
    x86_64-w64-mingw32-strip "$OUT_CLI"
    [ -f "$OUT_GUI" ] && x86_64-w64-mingw32-strip "$OUT_GUI"
fi

echo "==> 完成"
ls -la "$OUT_CLI" "$OUT_GUI" 2>/dev/null || ls -la "$BUILD"

if [ "$TARGET" = "windows" ]; then
    echo ""
    echo "✅ Windows 可执行文件已生成（静态链接，仅依赖系统 DLL）"
    echo ""
    for f in "$OUT_CLI" "$OUT_GUI"; do
        [ -f "$f" ] && file "$f"
    done
    echo ""
    echo "使用方法："
    echo "  命令行：  mkthumb.exe photo.png"
    echo "  窗口版：  mkthumb-gui.exe（拖图片进窗口即可）"
fi
