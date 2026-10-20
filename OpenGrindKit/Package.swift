// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The Rust bridge ships as `opengrind_coreFFI`: an XCFramework on Apple platforms
// (built by scripts/build-core-xcframework.sh) and a system library on Linux, where
// OPENGRIND_CORE_LIB_DIR names the directory holding libopengrind_core.so (the Nix
// `core` package sets it). Without it, Linux builds leave the bridge out and only
// build and test the pure Swift parts.
let coreLibraryDirectory = ProcessInfo.processInfo.environment["OPENGRIND_CORE_LIB_DIR"]

#if os(Linux)
    let coreTargets: [Target] =
        coreLibraryDirectory.map { directory in
            [
                .systemLibrary(name: "opengrind_coreFFI", path: "Sources/opengrind_coreFFI"),
                .target(
                    name: "OpenGrindCore",
                    dependencies: ["opengrind_coreFFI"],
                    swiftSettings: [.swiftLanguageMode(.v5)],
                    linkerSettings: [.unsafeFlags(["-L\(directory)", "-Xlinker", "-rpath", "-Xlinker", directory])]
                ),
            ]
        } ?? []
#else
    let coreTargets: [Target] = [
        .binaryTarget(name: "opengrind_coreFFI", path: "Frameworks/opengrind_coreFFI.xcframework"),
        .target(
            name: "OpenGrindCore",
            dependencies: ["opengrind_coreFFI"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
#endif

let withCore = !coreTargets.isEmpty

let package = Package(
    name: "OpenGrindKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "OpenGrindKit", targets: ["OpenGrindKit"]),
        // Shared build of the same target, installed by the Nix package.
        .library(name: "OpenGrindKitShared", type: .dynamic, targets: ["OpenGrindKit"]),
    ]
        + (withCore ? [.library(name: "OpenGrindCoreTransport", targets: ["OpenGrindCoreTransport"])] : []),
    targets: [
        .target(name: "OpenGrindKit"),
        .testTarget(name: "OpenGrindKitTests", dependencies: ["OpenGrindKit"]),
    ]
        + coreTargets
        + (withCore
            ? [
                .target(name: "OpenGrindCoreTransport", dependencies: ["OpenGrindKit", "OpenGrindCore"]),
                .testTarget(name: "OpenGrindCoreTransportTests", dependencies: ["OpenGrindCoreTransport"]),
            ] : [])
)
