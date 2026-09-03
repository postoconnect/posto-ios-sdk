// swift-tools-version: 5.9
import PackageDescription

// Public binary package for the Posto iOS SDK. Each release points at the
// compiled XCFramework served from postoconnect.com; the url and checksum are
// rewritten by the release tooling, never by hand.
let package = Package(
    name: "Posto",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Product "Posto", module "PostoSDK": integrators `import PostoSDK`.
        .library(name: "Posto", targets: ["PostoSDK"])
    ],
    targets: [
        .binaryTarget(
            name: "PostoSDK",
            url: "https://postoconnect.com/sdk/ios/0.0.0/PostoSDK.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    ]
)
