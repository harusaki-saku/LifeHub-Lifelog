# ios-lifelog

Apple Watch/iPhoneのHealthKitデータ（睡眠・運動）をLifeHubに送るネイティブアプリ。
設計の経緯・決定事項は `ideas/aiChat/ideaLifelog.md`（正本）を参照。

## ⏸️ 現在のステータス: 保留中

HealthKit entitlementが`.swiftpm`形式で設定できるか未検証のまま保留している（Mac/クラウドMac確保待ち）。
**再開時はまず`ideaLifelog.md`の§0-9・§0-10を読むこと。** 課題整理と、MacinCloud等でMacを確保した際の作業手順（Xcodeで何を確認し、ダメだった場合に何をするか）を記録済み。

## この場所について

`SideWork/apps/lifehub` monorepo内に同居しているが、他の`apps/*`（Next.js）とは技術スタックが異なるため、
npm workspacesの対象からは明示的に除外している（ルート`package.json`の`workspaces`に`!apps/ios-lifelog`を追加済み）。

## プロジェクト形式について（重要な注意）

`Lifelog.swiftpm/` は **Swift Playgrounds App Playground形式**（`AppleProductTypes`の`.iOSApplication`を使うSwiftPMパッケージ）でスキャフォールドしている。
この形式はiPadのSwift Playgroundsアプリでそのまま開けるほか、Xcode 14以降でも`.swiftpm`フォルダを直接開いて実機ビルドできる。
`ideaLifelog.md`で確定した「MVPはWatch拡張なし・単一ターゲットのiOSアプリなのでMacなしで着手できる」という方針に対応するための構成。

**このリポジトリ環境（Windows、Swiftツールチェーンなし）ではビルド・コンパイル検証ができていない。**
`Package.swift`の`AppleProductTypes` APIはSwiftツールバージョンによって微妙にパラメータが異なることがあるため、
**iPadのSwift PlaygroundsまたはXcodeで最初に開いたときにビルドエラーが出た場合は、その場でAPIシグネチャを合わせて調整してほしい。**
コード自体（HealthKit連携・同期ロジック・認証フロー）のロジックは意図通りに動く前提で書いているが、
Package.swiftのプロダクト定義部分だけは実機/実環境での確認が必須。

## 開いてから埋める必要がある項目

`Sources/Config.swift` にプレースホルダーが入っている。以下を実際の値に差し替えること。

| 項目 | 差し替え元 |
|------|-----------|
| `apiBaseURL` | `lifelog-api-stack` デプロイ後のAPI Gateway URL |
| `cognitoClientId` | `SideWork/infra/auth/cdk/lib/cognito-stack.ts`に追加済みの`showlabo-lifelog-ios`クライアント。デプロイ後、SSM `/showlabo/cognito/lifelog-ios-client-id` の値を取得して差し替える |
| `bundleIdentifier`（Package.swift） | 実際に使うBundle ID（現在 `com.showlabo.lifehub.lifelog` の仮値） |
| `teamIdentifier`（Package.swift） | Apple Developer AccountのTeam ID |

## ⚠️ HealthKit entitlementについて重要な発見（2026-07-11）

GitHub Actions CIでのビルド失敗を通じて判明: `AppleProductTypes`の`Capability` enumには**HealthKitのケースが存在しない**。
capabilities配列で表現できるのはCamera/Location/Microphone等、Info.plistの利用目的文言だけで完結する権限のみで、
HealthKitのような「Apple Developer PortalのApp ID側でcapability自体を有効化する必要がある」entitlement系は
App Playground形式のPackage.swiftからは設定できない可能性が高い。

**影響**: `import HealthKit`してAPIを呼ぶだけならCIでのコンパイルは通る（Package.swiftからは`.healthKit()`を削除済み）。
しかし実機で`HKHealthStore.requestAuthorization`が実際に許可されるかは別問題で、おそらく以下のどちらかが必要:

1. Xcodeで`Lifelog.swiftpm`を一度開き、「Signing & Capabilities」タブから"HealthKit"を追加する
   （これによりentitlementsファイルが自動生成される。**この操作にはXcode = Macが必要**）
2. または、それでも追加できない場合は本格的な`.xcodeproj`ベースのプロジェクトへの移行が必要になる可能性がある

**つまり「MVPはMacなしで完結する」という当初の想定は、HealthKit entitlementの設定については崩れている可能性がある。**
CI（GitHub Actions）でのビルド確認や、HealthKit以外のロジック（認証・API通信・UI）の検証はMacなしで進められるが、
実機でHealthKitの許可ダイアログが実際に機能するかは、Xcodeでの一度の確認が必要になる見込み。
借りたMac/クラウドMacで「Signing & Capabilities」に"HealthKit"を追加できるか、まずそこだけ検証するのが次の一歩として有効。

## HealthKit利用目的の文言（Info.plist相当）

Usage Description（`NSHealthShareUsageDescription`等）は`additionalInfoPlistContentFilePath`パラメータで
別のplistファイルを指定するか、上記のSigning & Capabilities設定と合わせてXcodeの「Info」タブから追加する必要がある。

## 実装済みのロジック（決定事項との対応）

| ファイル | 内容 |
|----------|------|
| `HealthKitManager.swift` | `HKAnchoredObjectQuery` + アンカー永続化による増分同期。`HKObserverQuery` + `enableBackgroundDelivery`で自動プッシュ。初回は`Config.initialBackfillDays`（30日）遡って取得 |
| `SyncModels.swift` | HealthKitの生サンプル（ソース情報込み）をそのままAPIに送るペイロード定義。**重複排除（ソース優先順位）と日付境界（起床日基準）はサーバー側で解決する設計**のため、クライアント側では加工しない |
| `AuthManager.swift` | Cognito Hosted UIに対するOAuth2 PKCE認証（`ASWebAuthenticationSession`）。トークンはKeychain保存 |
| `LifelogAPIClient.swift` | `POST /logs/raw` に生サンプル配列をまとめて送信 |

## 未実装・TODO

- **HealthKit entitlementが実機で有効化できるかの検証（最優先。上記参照）**
- HealthKit利用目的文言の設定（上記）
- アプリアイコン・Bundle ID・Team IDの本番値差し替え
