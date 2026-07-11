// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

// NOTE (2026-07-11 CI失敗を受けて修正):
// AppleProductTypesの `Capability` enumにはHealthKitのケースが存在しない
// （GitHub Actions上のビルドエラーで判明。コミュニティ収集のAPI一覧でも確認済み）。
// App Playground形式のcapabilities配列は主にInfo.plistの利用目的文言で完結する権限
// （camera, location, microphone等）向けで、HealthKitのような「Apple Developer Portor
// のApp ID側でcapabilityを有効化する必要がある」種類のentitlementはここでは扱えない。
// → HealthKit自体は`import HealthKit`してAPIを呼ぶだけなら本ファイルの変更なしにコンパイルは通るが、
//   実機でHKHealthStore.requestAuthorizationが本当に許可されるかは、Xcodeで一度開いて
//   Signing & Capabilitiesタブから"HealthKit"を追加し、entitlementsファイルを生成しないと
//   検証できない可能性が高い（未検証。詳細はideaLifelog.md参照）。
// appCategoryも `.healthAndFitness` ではなく `.healthcareFitness` が正しいケース名だった。
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
            appCategory: .healthcareFitness
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
