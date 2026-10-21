#!/bin/bash
# Build build/Saycribe.app (release), bundle sherpa-onnx dylibs + SenseVoice model, sign, and install to ~/Applications.
# The bundle id stays com.zjh.suikou (the app's original name) so granted permissions and saved settings carry over.
set -euo pipefail
cd "$(dirname "$0")/.."

SHERPA=vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts
MODEL=vendor/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09
APP=build/Saycribe.app
IDENTITY="${SUIKOU_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"

swift build -c release --disable-sandbox
BIN=$(swift build -c release --disable-sandbox --show-bin-path)/Suikou

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/models/sense-voice"
cp "$BIN" "$APP/Contents/MacOS/Saycribe"
cp "$SHERPA/lib/libsherpa-onnx-c-api.dylib" "$SHERPA/lib/libonnxruntime.dylib" "$APP/Contents/Frameworks/"
cp -R Resources/prompts "$APP/Contents/Resources/"
cp "$MODEL/model.int8.onnx" "$MODEL/tokens.txt" "$APP/Contents/Resources/models/sense-voice/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[ -f Resources/MenuBarIcon.png ] && cp Resources/MenuBarIcon*.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.zjh.suikou</string>
  <key>CFBundleName</key><string>Saycribe</string>
  <key>CFBundleDisplayName</key><string>Saycribe</string>
  <key>CFBundleExecutable</key><string>Saycribe</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Saycribe 需要麦克风来听你说话。录音只在本机识别，不会上传。</string>
</dict></plist>
PLIST

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"/Contents/Frameworks/*.dylib
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "no signing identity; ad-hoc signing (permissions reset on every rebuild)"
  codesign --force --sign - "$APP"/Contents/Frameworks/*.dylib
  codesign --force --sign - "$APP"
fi

mkdir -p ~/Applications
rm -rf ~/Applications/Saycribe.app ~/Applications/Suikou.app
cp -R "$APP" ~/Applications/
echo "installed ~/Applications/Saycribe.app (signed by: ${IDENTITY:-ad-hoc})"
