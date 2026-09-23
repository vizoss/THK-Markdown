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
        ),
        .library(name: "MarkdownFixtures", targets: ["MarkdownFixtures"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", revision: "75e3df1d7b664ef3c96595de36c243b98599b3bc")
    ],
    targets: [
        .target(name: "MarkdownFixtures", path: "Fixtures", resources: [.copy("data")]),
        .target(
            name: "THKMDView",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            // CocoaPods distributes an XCFramework built from these same sources.
            resources: [
                .copy("mermaid_template.html"),
                .copy("mermaid.min.js")
            ]
        ),
        .testTarget(
            name: "THKMDViewTests",
            dependencies: ["THKMDView", "MarkdownFixtures"],
            path: "Tests",
            sources: ["THKMDViewTests", "Shared"]
        )
    ]
)
