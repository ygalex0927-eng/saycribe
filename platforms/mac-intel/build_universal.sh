#!/bin/bash
# Saycribe Intel / 通用包构建（第 16 项）。只读主仓库的 Sources/、Resources/、vendor/、scripts/，不改它们。
#
# 用法：
#   platforms/mac-intel/build_universal.sh                 # 通用包 arm64+x86_64（默认）
#   platforms/mac-intel/build_universal.sh --arch x86_64   # 只出 Intel 包
#   platforms/mac-intel/build_universal.sh --arch arm64    # 只出 Apple 芯片包（对照用）
#   加 --selftest a.wav [style]  构建后对每个架构跑 --selftest（x86_64 在 Apple 芯片上走 Rosetta: arch -x86_64）
#   加 --git-ref <ref>   用某个提交里的 Sources/ 和 Package.swift 构建（例如 HEAD），避开工作区里正在改的半成品
#   加 --keep-stage       保留 .stage/ 临时构建目录（默认构建完删除）
# 产物：platforms/mac-intel/build/Saycribe-<arch>.app（不安装到 ~/Applications，避免覆盖主 Mac 版）
# 签名：SUIKOU_SIGN_IDENTITY 或第一个 Apple Development 证书，没有则 ad-hoc。
# 依赖：sherpa-onnx v1.13.8 官方 osx-universal2-shared-lib（含 universal2 的 libonnxruntime），
#       没有会自动下载到 platforms/mac-intel/vendor/（走系统代理；Mac 直连 github 不通时需开代理）。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
VER=1.13.8
PKG="sherpa-onnx-v$VER-osx-universal2-shared-lib"
SHA=c1cca5b4a1867543e27d42fbea513983e73f629d0aa53b43b51555a71d2108d9
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v$VER/$PKG.tar.bz2"
MODEL="$ROOT/vendor/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
KOKORO="$ROOT/vendor/kokoro-en-v0_19"
VAD="$ROOT/vendor/vad/silero_vad.onnx"
HEADERS="$ROOT/vendor/sherpa-onnx-v$VER-osx-arm64-shared/include"   # c-api.h 与架构无关

ARCH=universal; SELFTEST=(); KEEP=0; REF=""
while [ $# -gt 0 ]; do case "$1" in
  --arch) ARCH="$2"; shift 2;;
  --selftest) shift; SELFTEST=("$@"); break;;
  --keep-stage) KEEP=1; shift;;
  --git-ref) REF="$2"; shift 2;;
  -h|--help) sed -n 2,14p "$0"; exit 0;;
  *) echo "unknown arg $1"; exit 2;;
esac; done
case "$ARCH" in universal) ARCHS="arm64 x86_64";; arm64|x86_64) ARCHS="$ARCH";; *) echo "--arch 只能是 universal|arm64|x86_64"; exit 2;; esac

# 1. 通用版 sherpa-onnx 库
LIB="$HERE/vendor/$PKG/lib"
if [ ! -f "$LIB/libsherpa-onnx-c-api.dylib" ]; then
  mkdir -p "$HERE/vendor/dl"
  TAR="$HERE/vendor/dl/$PKG.tar.bz2"
  [ -f "$TAR" ] || curl -fL --retry 3 -o "$TAR" "$URL"
  echo "$SHA  $TAR" | shasum -a 256 -c -
  tar xjf "$TAR" -C "$HERE/vendor"
fi
for a in $ARCHS; do for d in libsherpa-onnx-c-api.dylib libonnxruntime.dylib; do
  lipo "$LIB/$d" -verify_arch "$a" || { echo "$d 缺 $a"; exit 1; }; done; done

# 2. 临时副本：只把 Package.swift 的库路径、shim.h 的头文件路径改指向，主仓库文件不动
STAGE="$HERE/.stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
if [ -n "$REF" ]; then
  git -C "$ROOT" archive "$REF" Sources Package.swift | tar x -C "$STAGE"; mv "$STAGE/Package.swift" "$STAGE/Package.swift.orig"
else
  cp -R "$ROOT/Sources" "$STAGE/Sources"; cp "$ROOT/Package.swift" "$STAGE/Package.swift.orig"
fi
sed "s#^let sherpaLib = .*#let sherpaLib = \"$LIB\"#" "$STAGE/Package.swift.orig" > "$STAGE/Package.swift"; rm "$STAGE/Package.swift.orig"
grep -q "let sherpaLib = \"$LIB\"" "$STAGE/Package.swift" || { echo "Package.swift 格式变了，需要更新本脚本"; exit 1; }
printf '#include "%s/sherpa-onnx/c-api/c-api.h"\n' "$HEADERS" > "$STAGE/Sources/CSherpa/shim.h"

# 3. 逐架构编译
BINS=()
for a in $ARCHS; do
  echo "== swift build $a"
  ( cd "$STAGE" && swift build -c release --disable-sandbox --triple "$a-apple-macosx14.0" )
  BINS+=("$(cd "$STAGE" && swift build -c release --disable-sandbox --triple "$a-apple-macosx14.0" --show-bin-path)/Suikou")
done

# 4. 组装 .app（结构与 scripts/build_app.sh 一致）
APP="$HERE/build/Saycribe-$ARCH.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/models/sense-voice" "$APP/Contents/Resources/models/vad" "$APP/Contents/Resources/models/kokoro"
if [ ${#BINS[@]} -gt 1 ]; then lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Saycribe"; else cp "${BINS[0]}" "$APP/Contents/MacOS/Saycribe"; fi
for d in libsherpa-onnx-c-api.dylib libonnxruntime.dylib; do
  if [ "$ARCH" = universal ]; then cp "$LIB/$d" "$APP/Contents/Frameworks/"; else lipo "$LIB/$d" -thin "$ARCH" -output "$APP/Contents/Frameworks/$d"; fi
done
cp -R "$ROOT/Resources/prompts" "$APP/Contents/Resources/"
cp "$MODEL/model.int8.onnx" "$MODEL/tokens.txt" "$APP/Contents/Resources/models/sense-voice/"
cp "$VAD" "$APP/Contents/Resources/models/vad/"
cp -R "$KOKORO/model.onnx" "$KOKORO/voices.bin" "$KOKORO/tokens.txt" "$KOKORO/espeak-ng-data" "$APP/Contents/Resources/models/kokoro/"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
ls "$ROOT"/Resources/MenuBarIcon*.png >/dev/null 2>&1 && cp "$ROOT"/Resources/MenuBarIcon*.png "$APP/Contents/Resources/"
# Info.plist 直接取主构建脚本里的那份，保证一致
awk '/<<.PLIST.$/{f=1;next} /^PLIST$/{f=0} f' "$ROOT/scripts/build_app.sh" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="${SUIKOU_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"/Contents/Frameworks/*.dylib
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "== $APP (signed by: ${IDENTITY:-ad-hoc})"
for f in "$APP/Contents/MacOS/Saycribe" "$APP"/Contents/Frameworks/*.dylib; do echo "  $(basename "$f"): $(lipo -archs "$f")"; done

[ $KEEP = 1 ] || rm -rf "$STAGE"

# 5. 自测
if [ ${#SELFTEST[@]} -gt 0 ]; then
  for a in $ARCHS; do
    echo "== selftest $a $( [ "$a" = x86_64 ] && [ "$(uname -m)" = arm64 ] && echo '(Rosetta)' || true)"
    arch -"$a" "$APP/Contents/MacOS/Saycribe" --selftest "${SELFTEST[@]}"
  done
fi
