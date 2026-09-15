// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hingewave",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hingewave", targets: ["Hingewave"]),
        .library(name: "HingewaveCore", targets: ["HingewaveCore"]),
    ],
    targets: [
        .target(
            name: "HingewaveCore",
            path: "Sources/HingewaveCore"
        ),
        .executableTarget(
            name: "Hingewave",
            dependencies: ["HingewaveCore"],
            path: "Sources/Hingewave",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "HingewaveCoreTests",
            dependencies: ["HingewaveCore"],
            path: "Tests/HingewaveCoreTests"
        ),
    ]
)
