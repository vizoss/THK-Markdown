// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "THKMDView",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "THKMDView", targets: ["THKMDView"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", revision: "75e3df1d7b664ef3c96595de36c243b98599b3bc")
    ],
    targets: [
        .target(
            name: "THKMDView",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "ios/Sources/THKMDView",
            resources: [
                .copy("mermaid_template.html"),
                .copy("mermaid.min.js"),
                .copy("math_template.html"),
                .copy("mathjax-3.2.2.js"),
                .copy("mathjax-LICENSE.txt")
            ]
        )
    ]
)
