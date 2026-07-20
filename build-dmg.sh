#!/bin/bash
# 确保本级环境已安装 create-dmg

# ========== 配置区 ==========
APP_NAME="MacTools"           # 你的应用名称
SCHEME_NAME="MacTools"        # Xcode Scheme
VERSION="1.0.0"
BUILD_DIR="./build"
OUTPUT_DIR="./dist"
# ===========================

set -e  # 遇到错误立即退出

echo "🧹 清理旧文件..."
rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "🔨 Xcode 构建 Release..."
xcodebuild \
  -scheme "${SCHEME_NAME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  -quiet

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ 构建失败，找不到: ${APP_PATH}"
    exit 1
fi
echo "✅ 构建成功: ${APP_PATH}"

echo "📦 准备 DMG 内容..."
TMP_DIR="${BUILD_DIR}/dmg-staging"
mkdir -p "${TMP_DIR}"
cp -R "${APP_PATH}" "${TMP_DIR}/"

echo "💿 创建 DMG..."
create-dmg \
  --volname "${APP_NAME} ${VERSION}" \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 160 185 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 500 185 \
  --format UDZO \
  --no-internet-enable \
  "${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg" \
  "${TMP_DIR}"

echo ""
echo "🎉 打包完成！"
echo "📍 文件位置: ${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg"
echo "📦 文件大小: $(du -h "${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg" | cut -f1)"