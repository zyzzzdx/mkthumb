#!/bin/bash
# 图片缩略图工具 —— 命令行入口
#
# 用法：mkthumb <文件...>
# 后端调用已编译的 ITMThumbnailGenerator（ImageIO 实现，
# 与 Finder 扩展共用同一套核心逻辑），而非 sips ——
# 因为 sips 无法精确控制 JPEG 压缩质量。
#
# 环境变量可覆盖默认配置：
#   ITM_FORMAT=jpg|png  ITM_QUALITY=low|medium|high
#   ITM_MAXPIXEL=800    ITM_SUFFIX=_thumb

set -uo pipefail

# 生成器位置：优先用安装到 ~/.local/bin 的版本，
# 其次回退到源码树里的构建产物（开发时用）
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$HOME/.local/bin/thumbgen" ]; then
    BIN="$HOME/.local/bin/thumbgen"
elif [ -x "$SELF_DIR/build/thumbgen" ]; then
    BIN="$SELF_DIR/build/thumbgen"
else
    osascript -e 'display notification "核心程序未编译，请先执行 build.sh" with name "图片缩略图工具"' 2>/dev/null
    exit 127
fi

if [ $# -eq 0 ]; then
    exit 0
fi

# 收集结果（thumbgen 输出 OK:<路径> / ERR:<信息>）
GENERATED=()
FAILED=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        OK:*)  GENERATED+=("${line#OK:}") ;;
        ERR:*) FAILED+=("${line#ERR:}") ;;
    esac
done <<< "$("$BIN" "$@" 2>&1)"

# 成功反馈
if [ ${#GENERATED[@]} -gt 0 ]; then
    if [ ${#GENERATED[@]} -eq 1 ]; then
        osascript -e 'display notification "已生成 1 个缩略图" with name "图片缩略图工具"' 2>/dev/null
    else
        osascript -e "display notification \"已生成 ${#GENERATED[@]} 个缩略图\" with name \"图片缩略图工具\"" 2>/dev/null
    fi
fi

# 有失败则提示（整批有失败才算整体失败）
if [ ${#FAILED[@]} -gt 0 ]; then
    MSG=$(printf '%s' "${FAILED[0]}" | cut -c1-100)
    osascript -e "display notification \"$MSG\" with name \"图片缩略图工具\"" 2>/dev/null
    [ ${#GENERATED[@]} -eq 0 ] && exit 1
fi

exit 0
