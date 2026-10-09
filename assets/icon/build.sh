#!/bin/bash
# 由 SVG 源文件生成各平台图标（需要 macOS）：
#   macos/Resources/AppIcon.icns      macOS App 图标
#   windows/src/CUITNet.App/app.ico   Windows 程序 / 托盘图标（16-256 多尺寸）
#   windows/src/CUITNet.App/app.png   Windows 窗口标题区的图标
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swiftc -O render.swift -o "$TMP/render"
R="$TMP/render"

# macOS：带圆角底板的版本
ICONSET="$TMP/AppIcon.iconset" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  "$R" app-icon.svg "$ICONSET/icon_${s}x${s}.png" $s
  "$R" app-icon.svg "$ICONSET/icon_${s}x${s}@2x.png" $((s * 2))
done
mkdir -p "$ROOT/macos/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/macos/Resources/AppIcon.icns"

# Windows：直角满版（系统不会再加遮罩）
for s in 16 20 24 32 40 48 64 256; do "$R" app-icon-flat.svg "$TMP/w$s.png" $s; done
python3 - "$TMP" "$ROOT/windows/src/CUITNet.App/app.ico" <<'PY'
import struct, sys
tmp, out = sys.argv[1], sys.argv[2]
sizes = [16, 20, 24, 32, 40, 48, 64, 256]
pngs = [open(f"{tmp}/w{s}.png", "rb").read() for s in sizes]
offset = 6 + 16 * len(sizes)
header = struct.pack("<HHH", 0, 1, len(sizes))
entries = b""
for s, data in zip(sizes, pngs):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
open(out, "wb").write(header + entries + b"".join(pngs))
PY
"$R" app-icon.svg "$ROOT/windows/src/CUITNet.App/app.png" 256
echo "图标已生成"
