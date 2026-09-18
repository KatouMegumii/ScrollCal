#!/bin/bash
# 生成 App 图标：iconset PNG -> AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"
OUTPUT="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ROOT/Resources"

echo "==> 渲染 PNG"
swift "$ROOT/Tools/GenerateIcon.swift" "$ICONSET"

echo "==> 打包 icns"
iconutil -c icns "$ICONSET" -o "$OUTPUT"

echo "==> 完成: $OUTPUT"
ls -la "$OUTPUT" | awk '{print "    体积: " $5 " 字节"}'
