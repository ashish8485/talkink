// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Soyle",
    platforms: [.macOS(.v14)],
    products: [
        // CLI used for de-risking, benchmarking and headless transcription.
        // The menu-bar GUI app is assembled from SoyleKit via scripts/ (see BUILDING.md).
        .executable(name: "soyle-cli", targets: ["SoyleCLI"]),
        .library(name: "SoyleKit", targets: ["SoyleKit"]),
    ],
    dependencies: [
        // Native Swift Nemotron 3.5 ASR (MLX). Pinned to a specific commit for reproducibility
        // (the package tracks `main` with no release tag).
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            revision: "417df212f54b8b4214a9815c1cd2eabb05fd4fdf"
        ),
    ],
    targets: [
        // Reusable core: the transcription engine, shared by the CLI and the GUI app.
        .target(
            name: "SoyleKit",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources/SoyleKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SoyleCLI",
            dependencies: ["SoyleKit"],
            path: "Sources/SoyleCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
