// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Broom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BroomCore", targets: ["BroomCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        // Code the hook helper and the app both need. No dependencies, so the helper starts fast.
        .target(
            name: "BroomShared",
            path: "Broom/Shared"
        ),
        .target(
            name: "BroomCore",
            dependencies: ["BroomShared", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Broom",
            exclude: ["App", "Live", "Inbox", "WorkstreamsTab", "Sweep", "History", "Search", "Debug", "MenuBar", "Design", "Settings", "Actions", "Shared", "Helpers"],
            sources: ["Engine", "Sources", "Index", "Workstreams"]
        ),
        .executableTarget(
            name: "broom-hook",
            dependencies: ["BroomShared"],
            path: "Broom/Helpers/broom-hook"
        ),
        .executableTarget(
            name: "Broom",
            dependencies: ["BroomCore", "BroomShared"],
            path: "Broom",
            exclude: ["Engine", "Sources", "Shared", "Helpers", "Index", "Workstreams"],
            sources: ["App", "Live", "Inbox", "WorkstreamsTab", "Sweep", "History", "Search", "Debug", "MenuBar", "Design", "Settings", "Actions"]
        ),
        .testTarget(
            name: "BroomCoreTests",
            dependencies: ["BroomCore", "BroomShared", "Broom", "broom-hook"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        )
    ]
)
