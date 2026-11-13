// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Quota", platforms: [.macOS(.v14)], products: [.executable(name: "Quota", targets: ["Quota"])], targets: [.executableTarget(name: "Quota", resources: [.process("Assets")]), .testTarget(name: "QuotaTests", dependencies: ["Quota"])], swiftLanguageModes: [.v5])
