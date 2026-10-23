// swift-tools-version: 5.9
// The app's platform-independent core (parsing, place matching, geofence planning),
// packaged so it can be tested anywhere with `swift test`, including on Linux CI.
// The iOS app compiles the same sources directly; open Pinscape.xcodeproj for the app.
import PackageDescription

let package = Package(
    name: "PinscapeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PinscapeCore", targets: ["PinscapeCore"]),
    ],
    targets: [
        .target(name: "PinscapeCore", path: "Shared/Core"),
        .testTarget(name: "PinscapeCoreTests", dependencies: ["PinscapeCore"], path: "PinscapeTests"),
    ]
)
