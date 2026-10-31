#!/usr/bin/env bash
# 交叉编译 platforms/core → asr-jni/src/main/jniLibs/<abi>/libsaycribe_core.so（只读 core 源码，产物放 core/target，不改 core 文件）
# 依赖：ANDROID_NDK_HOME（NDK r26+）、rustup target aarch64-linux-android x86_64-linux-android、cargo-ndk
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); CORE="$HERE/../core"
: "${ANDROID_NDK_HOME:?请设置 ANDROID_NDK_HOME}"
cd "$CORE"
cargo ndk -t arm64-v8a -t x86_64 -P 26 -o "$HERE/asr-jni/src/main/jniLibs" build --release --lib
# sherpa-onnx 在 android 只能 shared：把 libsherpa-onnx-c-api.so / libonnxruntime.so 一并拷入
for abi in arm64-v8a x86_64; do
  find target -path "*sherpa-onnx-prebuilt*/jniLibs/$abi/*.so" -exec cp {} "$HERE/asr-jni/src/main/jniLibs/$abi/" \;
done
ls -R "$HERE/asr-jni/src/main/jniLibs"
