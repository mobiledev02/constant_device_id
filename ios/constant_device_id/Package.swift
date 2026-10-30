// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "constant_device_id",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "constant-device-id", targets: ["constant_device_id"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "constant_device_id",
            dependencies: [],
            resources: []
        )
    ]
)

