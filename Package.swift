// swift-tools-version:5.3
// https://developer.apple.com/documentation/swift_packages/package
import PackageDescription

let package = Package(
    name: "SwiftNats",
    platforms: [
        .iOS(.v12),
    ],
    products: [
        .library(name: "SwiftNats", targets: ["SwiftNats"])
    ],
    path: []
    targets: [
        .target(
            name: "SwiftNats",
            exclude:["SwiftNats.h", "Info.plist"],
            path: "Sources"
        )
    ]
)