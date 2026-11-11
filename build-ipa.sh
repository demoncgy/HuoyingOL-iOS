#!/bin/bash
# ==============================================================================
# 火影OL iOS IPA 一键打包脚本 (适用于 macOS / Xcode)
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🚀 开始构建 火影OL iOS 版本..."

# 清理旧构建产物
rm -rf build
mkdir -p build

# 归档项目
echo "📦 正在执行 xcodebuild 归档..."
xcodebuild clean archive \
  -project HuoyingOL.xcodeproj \
  -scheme HuoyingOL \
  -destination "generic/platform=iOS" \
  -archivePath build/HuoyingOL.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

# 打包为 IPA
echo "📁 正在打包 Payload..."
mkdir -p build/Payload
cp -r build/HuoyingOL.xcarchive/Products/Applications/HuoyingOL.app build/Payload/

cd build
zip -qr HuoyingOL.ipa Payload

echo "✅ 打包完成！IPA 产物路径: $PROJECT_DIR/build/HuoyingOL.ipa"
echo "💡 提示: 此 IPA 为免签/Ad-hoc包，可通过以下方式直接安装到 iPhone/iPad："
echo "   1. 巨魔商店 (TrollStore) - 直接安装永久免签"
echo "   2. AltStore / SideStore - 自动用个人免费 Apple ID 签名安装"
echo "   3. 爱思助手 / Sideloadly - 连接电脑自签名安装"
