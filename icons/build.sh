#!/bin/sh
# 由 icons/*.svg（改颜色就编辑这些源文件）生成 dunst 等通知守护进程真正能加载的 PNG。
# 尺寸默认 48（dunst 的 min/max_icon_size 常见是 32/128，48 视觉最合适）；可用 SIZE=64 ./build.sh 调。
#
# 为什么必须出 PNG：很多通知守护进程走的 gdk-pixbuf 没有 SVG loader
# （本机 Arch 上 dunst 1.13 就是如此），SVG 图标会**静默不显示**。
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/png"
for svg in "$DIR"/*.svg; do
    name="$(basename "$svg" .svg)"
    rsvg-convert -w "${SIZE:-48}" -h "${SIZE:-48}" "$svg" -o "$DIR/png/$name.png"
    echo "  $name.svg -> png/$name.png"
done
