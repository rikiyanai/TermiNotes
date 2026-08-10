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
            exclude: [
                ".github", "Tests", "docs", "Info.plist", "README.md", "build.sh", "verify.sh",
                "terminotes_launcher.sh", "appicon.png", "appicon_display.png", "screenshot.png",
                "TermiNotes.app"
            ],
            sources: [
                "TermiNotesAppKit.swift",
                "TermiNotesStorage.swift",
                "TextLineIndex.swift",
                "ScreenshotPipeline.swift",
                "TerminalSanitizer.swift"
            ]
        )
    ]
)
