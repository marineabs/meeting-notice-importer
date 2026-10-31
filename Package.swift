// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingImporterCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MeetingImporterCore", targets: ["MeetingImporterCore"])
    ],
    targets: [
        .target(
            name: "MeetingImporterCore",
            path: "MeetingImporter",
            exclude: ["App", "Resources", "Views", "Services/APIKeyStore.swift", "Services/CalendarService.swift"],
            sources: [
                "Models/MeetingDraft.swift",
                "Services/MeetingTextParser.swift",
                "Services/MeetingAIShared.swift",
                "Services/ZhipuAIService.swift",
                "Services/MeetingAIService.swift"
            ]
        ),
        .testTarget(
            name: "MeetingImporterCoreTests",
            dependencies: ["MeetingImporterCore"]
        )
    ]
)
