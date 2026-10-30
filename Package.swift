// swift-tools-version:5.9
import PackageDescription

let sherpaLib = Context.packageDirectory + "/vendor/sherpa-onnx-v1.13.8-osx-arm64-shared/lib"

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
