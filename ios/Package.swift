// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "THKMDView",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "THKMDView",
            targets: ["THKMDView"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main")
    ],
    targets: [
        .target(
            name: "THKMDView",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(
            name: "THKMDViewTests",
            dependencies: ["THKMDView"]
        )
    ]
)
