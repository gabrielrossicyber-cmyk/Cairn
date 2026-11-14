// swift-tools-version: 5.9
// Tests automatisés de Cairn : `swift test` à la racine du dépôt.
//
// L'app elle-même se compile toujours avec SecuWiki.xcodeproj. Ce fichier sert uniquement à
// compiler le code de SecuWiki/ comme une bibliothèque pour pouvoir le tester sans interface.
import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CairnCore",
            path: "SecuWiki",
            // Le point d'entrée (@main) et les ressources ne font pas partie de la bibliothèque testée.
            exclude: ["App", "Assets.xcassets", "Preview", "Guide", "SecuWiki.entitlements"]
        ),
        .testTarget(
            name: "CairnTests",
            dependencies: ["CairnCore"],
            path: "Tests/CairnTests"
        ),
    ]
)
