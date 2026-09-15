// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacHinge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LidSensorKit", targets: ["LidSensorKit"]),
        .executable(name: "lid-sensor-cli", targets: ["LidSensorCLI"]),
        .executable(name: "MacHinge", targets: ["MacHinge"])
    ],
    targets: [
        .target(
            name: "LidSensorKit",
            dependencies: [],
            path: "Sources/LidSensorKit"
        ),
        .executableTarget(
            name: "LidSensorCLI",
            dependencies: ["LidSensorKit"],
            path: "Sources/LidSensorCLI"
        ),
        .executableTarget(
            name: "MacHinge",
            dependencies: ["LidSensorKit"],
            path: "Sources/MacHinge",
            resources: [
                .copy("Metal/Shaders.metal")
            ]
        ),
        .executableTarget(
            name: "machinge-bench",
            dependencies: ["LidSensorKit"],
            path: "Sources/MacHingeBenchmark"
        ),
        .testTarget(
            name: "MacHingeTests",
            dependencies: ["MacHinge", "LidSensorKit"],
            path: "Tests/MacHingeTests",
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
