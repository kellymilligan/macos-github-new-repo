// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NewRepo",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NewRepoCore"),
        .executableTarget(name: "NewRepo", dependencies: ["NewRepoCore"]),
        .testTarget(name: "NewRepoCoreTests", dependencies: ["NewRepoCore"]),
    ]
)
