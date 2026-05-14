// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CarelessWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CarelessWhisper", targets: ["CarelessWhisper"])
    ],
    targets: [
        .target(
            name: "WhisperBridge",
            path: "Sources/WhisperBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags([
                    "-IVendor/whisper.cpp/include",
                    "-IVendor/whisper.cpp/ggml/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "Vendor/whisper.cpp/build/src/libwhisper.a",
                    "Vendor/whisper.cpp/build/ggml/src/libggml.a",
                    "Vendor/whisper.cpp/build/ggml/src/libggml-base.a",
                    "Vendor/whisper.cpp/build/ggml/src/libggml-cpu.a",
                    "Vendor/whisper.cpp/build/ggml/src/ggml-blas/libggml-blas.a",
                    "-framework", "Accelerate",
                    "-lc++"
                ])
            ]
        ),
        .executableTarget(
            name: "CarelessWhisper",
            dependencies: ["WhisperBridge"],
            path: "Sources/CarelessWhisper"
        )
    ]
)
