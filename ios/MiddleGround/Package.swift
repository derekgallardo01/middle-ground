// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MiddleGround",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MiddleGround", targets: ["MiddleGround"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.3.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0")
    ],
    targets: [
        .target(
            name: "MiddleGround",
            dependencies: [
                "Factory",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk")
            ],
            path: "Sources/MiddleGround",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MiddleGroundTests",
            dependencies: ["MiddleGround"],
            path: "Tests/MiddleGroundTests"
        )
    ]
)
