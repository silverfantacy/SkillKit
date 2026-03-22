// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkillManager",
    defaultLocalization: "zh-Hant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SkillManagerApp",
            targets: ["SkillManagerApp"]
        ),
        .library(
            name: "SourceDiscovery",
            targets: ["SourceDiscovery"]
        ),
        .library(
            name: "SkillPersistence",
            targets: ["SkillPersistence"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "6.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "SkillManagerApp",
            dependencies: [
                "SourceDiscovery",
                "SkillPersistence"
            ],
            path: "Sources/SkillManagerApp",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SourceDiscovery"
        ),
        .target(
            name: "SkillPersistence",
            dependencies: [
                "SourceDiscovery",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "SourceDiscoveryTests",
            dependencies: [
                "SourceDiscovery",
                "TestSupport"
            ]
        ),
        .testTarget(
            name: "SkillPersistenceTests",
            dependencies: [
                "SkillPersistence",
                "TestSupport"
            ]
        ),
        .target(
            name: "TestSupport",
            path: "Tests/TestSupport"
        )
    ]
)
