#!/bin/bash
# 讯聊IM Android APK 打包脚本（仅 arm64，混淆+剥离符号，minSdk 30）
set -e

cd "$(dirname "$0")"

echo ">>> 正在打包 Android APK（arm64，混淆+剥离符号，仅新系统 minSdk 30）..."

# ✅ 关键：添加 --release
flutter build apk \
  --release \
  --target-platform=android-arm64 \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols

echo ""
APK_DIR="build/app/outputs/flutter-apk"
DESKTOP="$HOME/Desktop"
OUTPUT_NAME="壹信IM.apk"

if [ -f "$APK_DIR/app-release.apk" ]; then
  cp "$APK_DIR/app-release.apk" "$DESKTOP/$OUTPUT_NAME"
  echo "✅ 已复制到桌面: $OUTPUT_NAME"
else
  echo "❌ 打包失败：未找到 app-release.apk"
  exit 1
fi

echo ""
echo "📦 安装包路径: $(pwd)/$APK_DIR/app-release.apk"
echo "🖥️ 桌面文件: $DESKTOP/$OUTPUT_NAME"
