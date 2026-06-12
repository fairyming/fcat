#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ICONSET_DIR="$PROJECT_DIR/.build/FCat.iconset"
ICNS_PATH="$PROJECT_DIR/Resources/Icon/icon.icns"

SVG_PATH="$PROJECT_DIR/Resources/Icon/icon.svg"

echo "=== 生成 ICNS 图标 ==="

# 1. 检查转换工具
CONVERT_CMD=""
if command -v rsvg-convert &>/dev/null; then
    CONVERT_CMD="rsvg-convert"
elif command -v qlmanage &>/dev/null; then
    CONVERT_CMD="qlmanage"
elif python3 -c "import cairosvg" 2>/dev/null; then
    CONVERT_CMD="cairosvg"
else
    echo "警告：未找到 SVG 转换工具，尝试安装..."
    echo "  brew install librsvg   (推荐，提供 rsvg-convert)"
    echo "  pip3 install cairosvg   (备选)"
    echo ""
    echo "正在尝试使用 qlmanage (macOS 内置)..."

    # 使用 qlmanage 生成临时 PNG
    TMP_DIR="$PROJECT_DIR/.build/icon_tmp"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG_PATH" 2>/dev/null || true

    # qlmanage 输出文件名带有扩展名
    QL_OUTPUT="$TMP_DIR/icon.svg.png"
    if [ ! -f "$QL_OUTPUT" ]; then
        # 尝试查找 qlmanage 生成的任何 png
        QL_OUTPUT=$(find "$TMP_DIR" -name "*.png" -type f | head -1)
    fi

    if [ -z "$QL_OUTPUT" ] || [ ! -f "$QL_OUTPUT" ]; then
        echo "错误：无法转换 SVG，请安装转换工具："
        echo "  brew install librsvg"
        exit 1
    fi

    CONVERT_CMD="qlmanage_done"
    BASE_PNG="$QL_OUTPUT"
fi

# 2. 生成基础 1024x1024 PNG
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

BASE_PNG="$ICONSET_DIR/icon_1024x1024.png"

if [ "$CONVERT_CMD" = "rsvg-convert" ]; then
    rsvg-convert -w 1024 -h 1024 "$SVG_PATH" > "$BASE_PNG"
elif [ "$CONVERT_CMD" = "cairosvg" ]; then
    python3 -c "import cairosvg; cairosvg.svg2png(url='$SVG_PATH', write_to='$BASE_PNG', output_width=1024, output_height=1024)"
elif [ "$CONVERT_CMD" = "qlmanage_done" ]; then
    # 已在上面生成
    cp "$QL_OUTPUT" "$BASE_PNG"
    rm -rf "$PROJECT_DIR/.build/icon_tmp"
fi

# 3. 从 1024 PNG 生成各尺寸图标
sips -z 16 16     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png"         -s format png &>/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"      -s format png &>/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png"         -s format png &>/dev/null
sips -z 64 64     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"      -s format png &>/dev/null
sips -z 128 128   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png"       -s format png &>/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"    -s format png &>/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png"       -s format png &>/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"    -s format png &>/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png"       -s format png &>/dev/null
sips -z 1024 1024 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"    -s format png &>/dev/null

# 4. 使用 iconutil 生成 .icns
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "图标已生成：$ICNS_PATH"
ls -lh "$ICNS_PATH"