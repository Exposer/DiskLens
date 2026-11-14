// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskLens",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DiskLens", path: "Sources/DiskLens"),
        // 纯逻辑的单元测试(布局、对比、阈值、导出、缓存):swift test
        .testTarget(name: "DiskLensTests", dependencies: ["DiskLens"], path: "Tests/DiskLensTests")
    ]
)
