// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Umbra",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Umbra",
            path: "Sources/Umbra",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        // Test-only: creates virtual screens through a private macOS API. The app never links it.
        .target(name: "VirtualDisplay", path: "Sources/VirtualDisplay"),
        .testTarget(name: "UmbraTests", dependencies: ["Umbra", "VirtualDisplay"], path: "Tests/UmbraTests", resources: [.copy("Monitors")]),
    ]
)
