#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"

echo "=== FCat 打包脚本 ==="

# 1. 构建 Release 二进制
echo "[1/6] 构建 Release..."
swift build -c release --package-path "$PROJECT_DIR"

# 2. 获取二进制路径
EXECUTABLE="$(swift build -c release --package-path "$PROJECT_DIR" --show-bin-path)/FCat"
if [ ! -f "$EXECUTABLE" ]; then
    echo "错误：找不到 FCat 可执行文件"
    exit 1
fi

# 3. 生成图标
echo "[2/6] 生成图标..."
"$SCRIPT_DIR/icon.sh"

# 4. 创建 .app bundle
echo "[3/6] 创建 .app bundle..."
APP_DIR="$BUILD_DIR/FCat.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制可执行文件
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FCat"

# 复制 Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# 复制图标
ICNS_PATH="$PROJECT_DIR/Resources/Icon/icon.icns"
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# 创建 PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 5. 生成 DMG
echo "[4/6] 创建 DMG..."
DMG_DIR="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$APP_DIR" "$DMG_DIR/FCat.app"
ln -s /Applications "$DMG_DIR/Applications"

DMG_PATH="$BUILD_DIR/FCat.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "FCat" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

# 6. 清理临时文件
echo "[5/6] 清理..."
rm -rf "$DMG_DIR"

echo "[6/6] 完成！"
echo ""
echo "DMG 文件：$DMG_PATH"
echo "大小：$(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "安装方式：双击 DMG → 拖拽 FCat.app 到 Applications"