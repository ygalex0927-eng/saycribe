#!/bin/bash
# 编 platforms/core 的 iOS 静态库（device + simulator），并拷贝 SherpaOnnxC.xcframework。
# 互斥：/tmp/saycribe-ios-heavy.lock；1 分钟 load < 10 才开编。
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
LOCK=/tmp/saycribe-ios-heavy.lock
IOS="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$(cd "$IOS/../core" && pwd)"
EXPECT_SHA=fc4c665e694322ced5393aafafaae6bb3e0a7449d98d5db60bc220ac7ac4cbc9
EXPECT_SIZE=31577060
ZIP_NAME=sherpa-onnx-v2.0.1-ios-shared-onnxruntime-static.xcframework.zip
PREBUILT="$CORE/target/sherpa-onnx-prebuilt"
DEP_DIR="/Users/zjh/claude-workdir/suikou/依赖下载/ios-xcframework"

wait_load() {
  while true; do
    # uptime 输出: "... load averages: 1.2 3.4 5.6" —— 取 1 分钟值
    load1=$(uptime | sed -n 's/.*load averages: \([0-9.]*\).*/\1/p')
    echo "uptime load1=$load1"
    awk -v l="$load1" 'BEGIN{exit !(l+0 < 10)}' && break
    sleep 30
  done
}

acquire_lock() {
  while ! mkdir "$LOCK" 2>/dev/null; do
    echo "等待锁 $LOCK ..."
    sleep 15
  done
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
}

ensure_sherpa_zip() {
  mkdir -p "$PREBUILT"
  local z="$PREBUILT/$ZIP_NAME"
  if [[ -f "$z" ]]; then
    local sz sha
    sz=$(stat -f%z "$z")
    sha=$(shasum -a 256 "$z" | awk '{print $1}')
    if [[ "$sz" == "$EXPECT_SIZE" && "$sha" == "$EXPECT_SHA" ]]; then
      echo "prebuilt zip OK sha=$sha"
      return 0
    fi
    echo "prebuilt zip 不符 size=$sz sha=$sha，删除并改用依赖下载/"
    rm -f "$z"
  fi
  if [[ -f "$DEP_DIR/$ZIP_NAME" ]]; then
    cp "$DEP_DIR/$ZIP_NAME" "$z"
    sha=$(shasum -a 256 "$z" | awk '{print $1}')
    [[ "$sha" == "$EXPECT_SHA" ]] || { echo "依赖下载 zip sha 不对: $sha"; exit 1; }
    echo "已从依赖下载/ 拷入 prebuilt"
  else
    echo "缺少 $ZIP_NAME"; exit 1
  fi
}

wait_load
acquire_lock
ensure_sherpa_zip
# cargo 会读 target/sherpa-onnx-prebuilt；不设 ARCHIVE_DIR。下载 URL 由 sherpa-onnx-sys
# 对 *.xcframework.zip 使用 releases/download/xcframework/（不是 v2.0.1 tag）。

rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null
cd "$CORE"
for T in aarch64-apple-ios aarch64-apple-ios-sim; do
  echo "=== cargo build --release --target $T --features asr ==="
  cargo build --release --target "$T" --features asr
done

mkdir -p "$IOS/Vendor/core/ios-arm64" "$IOS/Vendor/core/ios-arm64-simulator"
cp -f target/aarch64-apple-ios/release/libsaycribe_core.a "$IOS/Vendor/core/ios-arm64/"
cp -f target/aarch64-apple-ios-sim/release/libsaycribe_core.a "$IOS/Vendor/core/ios-arm64-simulator/"

XC=$(find "$PREBUILT" -type d \( -name 'SherpaOnnxC.xcframework' -o -name 'sherpa-onnx.xcframework' \) | head -1)
[[ -n "$XC" && -d "$XC" ]] || { echo "未找到解压后的 xcframework"; exit 1; }
rm -rf "$IOS/Vendor/SherpaOnnxC.xcframework"
# 统一命名为 SherpaOnnxC.xcframework（project.yml 引用此名）
if [[ "$(basename "$XC")" == "SherpaOnnxC.xcframework" ]]; then
  cp -R "$XC" "$IOS/Vendor/SherpaOnnxC.xcframework"
else
  # sherpa-onnx.xcframework → 拷贝后仍可用，但 Xcode 依赖名要对；改名复制
  cp -R "$XC" "$IOS/Vendor/SherpaOnnxC.xcframework"
fi
ls -lh "$IOS/Vendor/core/ios-arm64/libsaycribe_core.a" "$IOS/Vendor/core/ios-arm64-simulator/libsaycribe_core.a"
ls -d "$IOS/Vendor/SherpaOnnxC.xcframework"
echo OK
