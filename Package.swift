// swift-tools-version:5.9
// NoSpy — privacy mic toggle for macOS.
// Two products will live here: `nospy` (CLI) and, after Step 4b, `NoSpyBar`
// (menu bar app). Both depend on NoSpyCore, which holds all the actual logic.

import PackageDescription

let package = Package(
    name: "NoSpy",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "nospy",    targets: ["nospy"]),
        .executable(name: "NoSpyBar", targets: ["NoSpyBar"]),
    ],
    targets: [
        .target(name: "NoSpyCore"),
        .executableTarget(name: "nospy",    dependencies: ["NoSpyCore"]),
        .executableTarget(name: "NoSpyBar", dependencies: ["NoSpyCore"]),
    ]
)
