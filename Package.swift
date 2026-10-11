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
        // whisper.cpp v1.9.5, prebuilt by the project. Speech turns into text inside Talky with it.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        .target(name: "TalkyCore", dependencies: [.product(name: "Sparkle", package: "Sparkle"), "whisper"]),
        .executableTarget(
            name: "Talky",
            dependencies: ["TalkyCore"],
            // build-app.sh copies Sparkle.framework and whisper.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TalkyCoreTests", dependencies: ["TalkyCore"]),
    ]
)
