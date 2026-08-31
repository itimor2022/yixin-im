#!/bin/bash
# 讯聊IM Android APK 打包脚本（仅 arm64，混淆+剥离符号，minSdk 30）
set -e

cd "$(dirname "$0")"

echo ">>> 正在打包 Android APK（arm64，混淆+剥离符号，仅新系统 minSdk 30）..."
# ✅ 关键：添加 --release
fvm use 3.47.2
fvm flutter clean
fvm flutter pub get
fvm flutter build apk \
  --release \
  --target-platform=android-arm64 \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols

echo ""
APK_DIR="build/app/outputs/flutter-apk"
DESKTOP="$HOME/data/apk"

# 创建桌面目录（如果不存在）
mkdir -p "$DESKTOP"

# 生成时间戳（格式：年月日_时分秒）
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_NAME="通用IM_${TIMESTAMP}.apk"

APK_SOURCE="$APK_DIR/app-release.apk"

if [ ! -f "$APK_SOURCE" ] && [ -f "$APK_DIR/app-arm64-v8a-release.apk" ]; then
  APK_SOURCE="$APK_DIR/app-arm64-v8a-release.apk"
fi

if [ -f "$APK_SOURCE" ]; then
  cp "$APK_SOURCE" "$DESKTOP/$OUTPUT_NAME"
  echo "✅ 已复制到桌面: $OUTPUT_NAME"
  
  # 显示文件大小
  FILE_SIZE=$(ls -lh "$DESKTOP/$OUTPUT_NAME" | awk '{print $5}')
  echo "📦 文件大小: $FILE_SIZE"
else
  echo "❌ 打包失败：未找到 release APK（app-release.apk / app-arm64-v8a-release.apk）"
  exit 1
fi

echo ""
echo "📦 安装包路径: $(pwd)/$APK_SOURCE"
echo "🖥️ 桌面文件: $DESKTOP/$OUTPUT_NAME"