// swift-tools-version: 6.0
import PackageDescription

// This manifest intentionally lives at the monorepo root. Swift Package
// Manager resolves remote Git dependencies only from a repository-root
// Package.swift; the client implementation itself remains under /swift.
let package = Package(
    name: "GreekPostalCodeDB",
    products: [
        .library(name: "GreekPostalCodeDB", targets: ["GreekPostalCodeDB"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "swift/Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
            ]
        ),
        .target(
            name: "GreekPostalCodeDB",
            dependencies: ["CSQLite"],
            path: ".",
            exclude: [
                ".build", ".github", "_logs", "csharp", "dart", "demo", "flutter", "go", "java",
                "models", "php", "python", "rust", "scripts", "typescript",
                "target", "vendor", "swift/Tests", "swift/Sources/CSQLite",
                "swift/CHANGELOG.md", "swift/LICENSE", "swift/README.md",
                "README.md", "LICENSE", "Cargo.toml", "Cargo.lock", "composer.json", "composer.lock",
                "phpunit.xml.dist", ".gitattributes", ".gitignore", ".editorconfig",
                ".phpunit.result.cache", "_update-notifier-last-checked",
            ],
            sources: ["swift/Sources/GreekPostalCodeDB"],
            resources: [.copy("library.sqlite")]
        ),
        .testTarget(
            name: "GreekPostalCodeDBTests",
            dependencies: ["GreekPostalCodeDB"],
            path: "swift/Tests/GreekPostalCodeDBTests"
        ),
    ]
)
