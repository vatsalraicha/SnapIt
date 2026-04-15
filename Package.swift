// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnapIt",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SnapIt", targets: ["SnapIt"]),
    ],
    targets: [
        .executableTarget(
            name: "SnapIt",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
