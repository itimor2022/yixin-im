#!/bin/bash
# 讯聊IM Web 打包脚本（带时间戳-简化版）
set -e

cd "$(dirname "$0")"

# 获取时间戳
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo ">>> 正在打包 Web 端（版本: $TIMESTAMP）..."

# 清理并构建
rm -rf build/web
flutter build web

# 复制到桌面（带时间戳）
OUTPUT_DIR="$HOME/data/web/"
cp -r build/web "$OUTPUT_DIR"

# 创建压缩包
cd "$OUTPUT_DIR"
zip -r "锦绣汇IM_Web_${TIMESTAMP}.zip" "web"
rm -rf "$OUTPUT_DIR/web"

echo "✅ 打包完成！"
echo "📦 文件: $OUTPUT_DIR/锦绣汇IM_Web_${TIMESTAMP}.zip"