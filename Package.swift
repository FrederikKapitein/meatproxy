// swift-tools-version: 6.0
// Tuinstra Meatproxy (D45): native Apple apps that show your Claude and ChatGPT/Codex work, and your Dark Software
// Factories, as a campus and an orbit. Approved by a human. Reviewed by nobody.
// This package is the Mac app: the collector, the shared model and the two worlds, Office and Orbit (SpriteKit).
import PackageDescription

let package = Package(
    name: "Meatproxy",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Meatproxy", targets: ["Meatproxy"]),
    ],
    dependencies: [
        // the terminal in the app (D57): a real VT100/xterm emulator with a local pseudo-terminal, MIT licensed
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.2"),
    ],
    targets: [
        // The model and the world grammar, shared by every platform (D13, D24).
        .target(name: "FactoryCore"),
        // Reads the providers' own session files. Mac only (D8, D17).
        .target(name: "FactoryCollector", dependencies: ["FactoryCore"]),
        // The worlds, rendered with SpriteKit (D13). The model does not know about the renderer.
        .target(name: "FactoryScenes", dependencies: ["FactoryCore"], resources: [.copy("Art")]),
        // the Mac app; its brand assets (the app icon) ship as resources
        .executableTarget(name: "Meatproxy", dependencies: ["FactoryCore", "FactoryCollector", "FactoryScenes", .product(name: "SwiftTerm", package: "SwiftTerm")],
                          resources: [.copy("Brand")]),
        .testTarget(name: "FactoryCollectorTests", dependencies: ["FactoryCollector", "FactoryCore"]),
        .testTarget(name: "FactoryCoreTests", dependencies: ["FactoryCore"]),
        .testTarget(name: "FactoryScenesTests", dependencies: ["FactoryScenes", "FactoryCore"]),
    ],
    swiftLanguageModes: [.v5]
)
