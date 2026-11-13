// swift-tools-version: 6.2
// open claude: a hotkey (control option command c) opens a laaabs. palette that asks for a folder
// and starts claude code there in a new terminal window.
import PackageDescription

let package = Package(
    name: "OpenClaude",
    platforms: [.macOS(.v14)],
    dependencies: [
        // the laaabs. kit, from the brand folder on this mac
        .package(path: "../../Desktop/laaabs/marca/ui-swift"),
        // the version LaaabsKit pins
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "OpenClaude",
            dependencies: [
                .product(name: "LaaabsKit", package: "ui-swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/OpenClaude"
        ),
        .testTarget(name: "OpenClaudeTests", dependencies: ["OpenClaude"], path: "Tests/OpenClaudeTests"),
    ]
)
