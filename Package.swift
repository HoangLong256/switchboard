// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 1.21 announces breaking changes, so stay on 1.20.x
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0")),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", .upToNextMinor(from: "2.4.1")),
    ],
    targets: [
        // Reads the Claude Code registry, transcripts, handovers and usage. Based on MIT-licensed code, see
        // Sources/SessionCore/LICENSE-upstream and LOCAL_CHANGES.md.
        .target(name: "SessionCore", exclude: ["LICENSE-upstream", "UPSTREAM_COMMIT", "LOCAL_CHANGES.md"]),
        // Folder listing and git status for the folder sidebar (no UI, so it can be tested)
        .target(name: "FolderKit"),
        // What the status line command keeps for the app (plan limits, context, cost per session)
        .target(name: "StatusLineKit"),
        // Editor tabs and documents with VS Code's preview, dirty and save-conflict rules (no UI, tested)
        .target(name: "EditorKit"),
        // Claude Code agent teams from ~/.claude/teams and ~/.claude/tasks (no UI, tested)
        .target(name: "TeamKit"),
        .executableTarget(name: "switchboard-statusline", dependencies: ["StatusLineKit"]),
        // Lets Claude keep its session's handover (~/.claude/handover/<session>.md), shown in the Handover tab
        .executableTarget(name: "switchboard-task", dependencies: ["SessionCore"]),
        .executableTarget(
            name: "Switchboard",
            dependencies: [
                "SessionCore", "FolderKit", "StatusLineKit", "EditorKit", "TeamKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(name: "FolderKitTests", dependencies: ["FolderKit"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"]),
        .testTarget(name: "TeamKitTests", dependencies: ["TeamKit"]),
        .testTarget(name: "StatusLineKitTests", dependencies: ["StatusLineKit", "SessionCore"]),
    ]
)
