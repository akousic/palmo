// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Palmo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Palmo", targets: ["Palmo"]),
        .library(name: "PalmoCore", targets: ["PalmoCore"]),
    ],
    targets: [
        .target(
            name: "PalmoCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Palmo",
            dependencies: ["PalmoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PalmoCoreTests",
            dependencies: ["PalmoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
