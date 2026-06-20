// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFPresenter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PDFPresenter",
            path: "Sources/PDFPresenter"
        )
    ],
    swiftLanguageVersions: [.v5]
)
