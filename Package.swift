// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "TermiNotes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TermiNotes", targets: ["TermiNotes"])
    ],
    targets: [
        .executableTarget(
            name: "TermiNotes",
            path: ".",
            exclude: ["Info.plist", "build.sh", "spec.md", "FAILURE_LOG.md", "dumpster"]
        )
    ]
)
