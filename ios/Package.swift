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
            ],
            // The CocoaPods distribution (see ../THKMDView.podspec) uses a different
            // Markdown parser (Maaku) that has no SPM-resolvable trunk release, so its
            // renderer lives in a sibling file under CocoaPods/ that SPM must never
            // compile. The podspec's own `exclude_files` mirrors this in the other
            // direction, excluding SPM/.
            exclude: ["CocoaPods"],
            // THKMermaidView.swift loads these via `Bundle.module`. The podspec declares the
            // same two files separately (as `s.resource_bundles`) since CocoaPods has no
            // `Bundle.module` equivalent — see THKMermaidView.swift's `resourceURL(name:ext:)`.
            resources: [
                .copy("mermaid_template.html"),
                .copy("mermaid.min.js")
            ]
        ),
        .testTarget(
            name: "THKMDViewTests",
            dependencies: ["THKMDView"]
        )
    ]
)
