// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

// NOTE: このPackage.swiftはWindows環境（Swiftツールチェーンなし）で作成しており、
// AppleProductTypesのAPIシグネチャを実機コンパイルで検証できていない。
// Swift Playgrounds / Xcodeで最初に開いてビルドエラーが出た場合は、
// エディタの自動補完に従ってこのファイルのパラメータを合わせること。

let package = Package(
    name: "Lifelog",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Lifelog",
            targets: ["AppModule"],
            bundleIdentifier: "com.showlabo.lifehub.lifelog", // TODO: 本番のBundle IDに差し替え
            teamIdentifier: "TEAMID_PLACEHOLDER",              // TODO: Apple Developer AccountのTeam ID
            displayVersion: "0.1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            capabilities: [
                .healthKit()
            ],
            appCategory: .healthAndFitness
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
