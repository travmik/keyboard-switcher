// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "keyboard-switcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyboardSwitcherCore", path: "Sources/KeyboardSwitcherCore"),
        .executableTarget(
            name: "KeyboardSwitcher",
            dependencies: ["KeyboardSwitcherCore"],
            path: "Sources/KeyboardSwitcher"
        ),
        .testTarget(
            name: "KeyboardSwitcherTests",
            dependencies: ["KeyboardSwitcherCore"],
            path: "Tests/KeyboardSwitcherTests"
        )
    ]
)
