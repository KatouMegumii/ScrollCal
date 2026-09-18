#!/bin/bash
# 重新构建并安装到 /Applications，然后重启 App。
# 用法：在终端里执行 ./install.sh（终端有权限，不受沙箱限制）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/Applications/ScrollCal.app"

"$ROOT/build.sh"

echo "==> 退出旧实例"
pkill -f "ScrollCal.app/Contents/MacOS/ScrollCal" 2>/dev/null || true
sleep 1

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$ROOT/build/ScrollCal.app" "$DEST"

echo "==> 启动"
open "$DEST"
sleep 1
pgrep -fl "ScrollCal" || echo "    (未检测到进程，请手动打开 $DEST)"
echo "==> 完成"
