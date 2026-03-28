// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AddFloatingWidget",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.0.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AddFloatingWidget",
            dependencies: [
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "PathKit", package: "PathKit"),
            ],
            path: "Sources"
        ),
    ]
)
