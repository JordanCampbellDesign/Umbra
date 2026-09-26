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
        .testTarget(name: "UmbraTests", dependencies: ["Umbra"], path: "Tests/UmbraTests"),
    ]
)
