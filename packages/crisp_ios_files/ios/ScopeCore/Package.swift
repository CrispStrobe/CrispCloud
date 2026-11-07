// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrispIosFilesCore",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [.library(name: "CrispIosFilesCore", targets: ["CrispIosFilesCore"])],
    targets: [
        .target(name: "CrispIosFilesCore"),
        .testTarget(name: "CrispIosFilesCoreTests", dependencies: ["CrispIosFilesCore"])
    ]
)
