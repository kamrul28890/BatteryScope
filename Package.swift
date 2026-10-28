// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryScope",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BatteryScope", targets: ["BatteryScope"])],
    targets: [
        .target(name: "BatteryCore"),
        .executableTarget(name: "BatteryScope", dependencies: ["BatteryCore"]),
        .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"])
    ],
    swiftLanguageModes: [.v5]
)
