// swift-tools-version:6.0
import PackageDescription

// Zero dependencies is a product contract (plan §3): a partner adds this
// package and gets no transitive baggage. Language mode v5 matches the
// shipped gateway-ios app the sources are extracted from; strict-concurrency
// adoption is a later, deliberate pass, not a scaffold default.
let package = Package(
    name: "EEGatewaySDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),   // enables swift test on mac + the Linux harness
    ],
    products: [
        .library(name: "EEGatewaySDK", targets: ["EEGatewaySDK"]),
    ],
    targets: [
        .target(
            name: "EEGatewaySDK",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EEGatewaySDKTests",
            dependencies: ["EEGatewaySDK"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
