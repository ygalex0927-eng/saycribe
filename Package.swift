// swift-tools-version:5.9
import PackageDescription
import Foundation

/// Sherpa-onnx root (contains `lib/` + `include/`), or a direct `…/lib` path.
/// - `SHERPA_ONNX_DIR`: absolute/relative override
/// - `SUIKOU_VENDOR_ARCH`: selects `vendor/sherpa-onnx-v1.13.8-osx-<arch>-shared` (default `arm64`)
/// `platforms/mac-intel/build_universal.sh` sed-replaces the `let sherpaLib =` line — keep that form.
func resolveSherpaRoot() -> String {
    let env = ProcessInfo.processInfo.environment
    if let dir = env["SHERPA_ONNX_DIR"], !dir.isEmpty { return dir }
    let arch = env["SUIKOU_VENDOR_ARCH"] ?? "arm64"
    return Context.packageDirectory + "/vendor/sherpa-onnx-v1.13.8-osx-\(arch)-shared"
}

let sherpaRoot = resolveSherpaRoot()
// Intel build_universal.sh sed-replaces this line with an absolute …/lib path.
let sherpaLib = sherpaRoot.hasSuffix("/lib") ? sherpaRoot : sherpaRoot + "/lib"

/// Header path written into Sources/CSherpa/shim.h (relative when using vendor/<arch>).
let sherpaHeaderInclude: String = {
    let env = ProcessInfo.processInfo.environment
    if let dir = env["SHERPA_ONNX_DIR"], !dir.isEmpty {
        let root = dir.hasSuffix("/lib") ? String(dir.dropLast(4)) : dir
        return root + "/include/sherpa-onnx/c-api/c-api.h"
    }
    // After intel sed, sherpaLib is absolute …/lib outside this repo; don't rewrite shim
    // (build_universal.sh overwrites shim.h itself). Only rewrite for vendor-layout builds.
    if !sherpaLib.contains("/vendor/sherpa-onnx-v1.13.8-osx-") {
        return ""
    }
    let arch = env["SUIKOU_VENDOR_ARCH"] ?? "arm64"
    return "../../vendor/sherpa-onnx-v1.13.8-osx-\(arch)-shared/include/sherpa-onnx/c-api/c-api.h"
}()

if !sherpaHeaderInclude.isEmpty {
    let shimPath = Context.packageDirectory + "/Sources/CSherpa/shim.h"
    let body = "#include \"\(sherpaHeaderInclude)\"\n"
    if (try? String(contentsOfFile: shimPath, encoding: .utf8)) != body {
        try? body.write(toFile: shimPath, atomically: true, encoding: .utf8)
    }
}

let package = Package(
    name: "Suikou",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CSherpa", path: "Sources/CSherpa"),
        .executableTarget(
            name: "Suikou",
            dependencies: ["CSherpa"],
            linkerSettings: [
                .unsafeFlags(["-L", sherpaLib, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
