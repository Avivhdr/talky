// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Talky",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Talky", targets: ["Talky"]),
    ],
    targets: [
        .target(name: "TalkyCore"),
        .executableTarget(name: "Talky", dependencies: ["TalkyCore"]),
        .testTarget(name: "TalkyCoreTests", dependencies: ["TalkyCore"]),
    ]
)
