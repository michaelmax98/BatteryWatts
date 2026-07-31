// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterBattery",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BetterBattery", targets: ["BetterBattery"])
    ],
    targets: [
        .executableTarget(
            name: "BetterBattery",
            path: "Sources/BetterBattery",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
