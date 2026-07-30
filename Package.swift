// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatteryWatts",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BatteryWatts", targets: ["BatteryWatts"])
    ],
    targets: [
        .executableTarget(
            name: "BatteryWatts",
            path: "Sources/BatteryWatts",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
