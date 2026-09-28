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
elif python3 -c "import cairosvg" 2>/dev/null; then
    CONVERT_CMD="cairosvg"
else
    echo "未找到 SVG 转换工具，尝试安装 librsvg..."
    if command -v brew &>/dev/null; then
        brew install librsvg
    fi
    if command -v rsvg-convert &>/dev/null; then
        CONVERT_CMD="rsvg-convert"
    else
        echo "错误：需要 rsvg-convert（由 librsvg 提供）来生成图标"
        exit 1
    fi
fi

# 2. 生成基础 1024x1024 PNG
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

BASE_PNG="$PROJECT_DIR/.build/FCat-icon-base.png"

if [ "$CONVERT_CMD" = "rsvg-convert" ]; then
    rsvg-convert -w 1024 -h 1024 "$SVG_PATH" > "$BASE_PNG"
elif [ "$CONVERT_CMD" = "cairosvg" ]; then
    python3 -c "import cairosvg; cairosvg.svg2png(url='$SVG_PATH', write_to='$BASE_PNG', output_width=1024, output_height=1024)"
fi

if [ ! -s "$BASE_PNG" ]; then
    echo "错误：SVG 转 PNG 未生成基础图标：$BASE_PNG"
    echo "转换器：${CONVERT_CMD:-none}"
    exit 1
fi

# 3. 从 1024 PNG 生成各尺寸图标。某些 macOS runner 上 sips 对输出
# 参数的处理不稳定；失败时保留一份有效 PNG，让后面的 ICNS 回退仍可用。
resize_icon() {
    local size="$1"
    local output="$2"
    if ! sips -s format png -z "$size" "$size" "$BASE_PNG" --out "$output" &>/dev/null; then
        cp "$BASE_PNG" "$output"
    fi
    if [ ! -s "$output" ]; then
        echo "错误：无法生成图标文件：$output"
        exit 1
    fi
}

resize_icon 16   "$ICONSET_DIR/icon_16x16.png"
resize_icon 32   "$ICONSET_DIR/icon_16x16@2x.png"
resize_icon 32   "$ICONSET_DIR/icon_32x32.png"
resize_icon 64   "$ICONSET_DIR/icon_32x32@2x.png"
resize_icon 128  "$ICONSET_DIR/icon_128x128.png"
resize_icon 256  "$ICONSET_DIR/icon_128x128@2x.png"
resize_icon 256  "$ICONSET_DIR/icon_256x256.png"
resize_icon 512  "$ICONSET_DIR/icon_256x256@2x.png"
resize_icon 512  "$ICONSET_DIR/icon_512x512.png"
resize_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

# 4. 直接使用标准 ICNS PNG chunk 生成 .icns。
# GitHub macOS runner 上的 iconutil 可能失败并清空 iconset，因此不依赖它。
mkdir -p "$(dirname "$ICNS_PATH")"
test -s "$BASE_PNG"
python3 - "$ICONSET_DIR" "$ICNS_PATH" <<'PY'
import pathlib
import struct
import sys

iconset = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
representations = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
chunks = []
for kind, filename in representations:
    payload = (iconset / filename).read_bytes()
    chunks.append(kind + struct.pack(">I", len(payload) + 8) + payload)
body = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY
rm -f "$BASE_PNG"

echo "图标已生成：$ICNS_PATH"
ls -lh "$ICNS_PATH"
