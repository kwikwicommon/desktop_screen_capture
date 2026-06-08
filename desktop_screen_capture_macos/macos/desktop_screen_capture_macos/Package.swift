// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "desktop_screen_capture_macos",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .library(name: "desktop-screen-capture-macos", targets: ["desktop_screen_capture_macos"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "desktop_screen_capture_macos",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
