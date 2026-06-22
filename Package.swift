// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFPresenter",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Shared by the macOS app and the iOS companion (its own Xcode project).
        .library(name: "PresenterKit", targets: ["PresenterKit"]),
    ],
    targets: [
        .target(
            name: "PresenterKit",
            path: "Sources/PresenterKit"
        ),
        .executableTarget(
            name: "PDFPresenter",
            dependencies: ["PresenterKit"],
            path: "Sources/PDFPresenter"
        ),
        .testTarget(
            name: "PresenterKitTests",
            dependencies: ["PresenterKit"],
            path: "Tests/PresenterKitTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
