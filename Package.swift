// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Talky",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Talky", targets: ["Talky"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .target(name: "TalkyCore", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(
            name: "Talky",
            dependencies: ["TalkyCore"],
            // build-app.sh copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TalkyCoreTests", dependencies: ["TalkyCore"]),
    ]
)
