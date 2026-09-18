#!/bin/bash
# 构建 ScrollCal.app（菜单栏滚动日历）
# 只依赖 CommandLineTools + swiftc，不需要完整 Xcode。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/ScrollCal.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macosx14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift 源码 (target: $TARGET)"
swiftc -O -parse-as-library \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-cache-path "$ROOT/build/ModuleCache" \
    -o "$APP/Contents/MacOS/ScrollCal" \
    "$ROOT/Sources/ScrollCal.swift" \
    "$ROOT/Sources/ChineseCalendar.swift"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICNS="$ROOT/Resources/AppIcon.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
    echo "==> 已内置图标 AppIcon.icns"
else
    echo "==> 未找到 AppIcon.icns（可执行 Tools/make-icon.sh 生成）"
fi

echo "==> 临时签名 (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || echo "    (codesign 跳过，不影响本机运行)"

echo "==> 完成: $APP"
du -sh "$APP" | awk '{print "    体积: " $1}'
