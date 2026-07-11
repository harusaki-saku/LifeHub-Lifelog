# ios-lifelog

Apple Watch/iPhoneのHealthKitデータ（睡眠・運動）をLifeHubに送るネイティブアプリ。
設計の経緯・決定事項は `ideas/aiChat/ideaLifelog.md`（正本）を参照。

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

## HealthKit利用目的の文言（Info.plist相当）

App Playground形式でのUsage Description（`NSHealthShareUsageDescription`等）の設定方法は、
Swift PlaygroundsまたはXcodeの「Info」設定UIから追加する必要がある（Package.swiftのプロダクト定義だけでは完結しない可能性が高い）。
初回オープン時に設定すること。

## 実装済みのロジック（決定事項との対応）

| ファイル | 内容 |
|----------|------|
| `HealthKitManager.swift` | `HKAnchoredObjectQuery` + アンカー永続化による増分同期。`HKObserverQuery` + `enableBackgroundDelivery`で自動プッシュ。初回は`Config.initialBackfillDays`（30日）遡って取得 |
| `SyncModels.swift` | HealthKitの生サンプル（ソース情報込み）をそのままAPIに送るペイロード定義。**重複排除（ソース優先順位）と日付境界（起床日基準）はサーバー側で解決する設計**のため、クライアント側では加工しない |
| `AuthManager.swift` | Cognito Hosted UIに対するOAuth2 PKCE認証（`ASWebAuthenticationSession`）。トークンはKeychain保存 |
| `LifelogAPIClient.swift` | `POST /logs/raw` に生サンプル配列をまとめて送信 |

## 未実装・TODO

- リフレッシュトークンによる自動更新
- HealthKit利用目的文言の設定（上記）
- アプリアイコン・Bundle ID・Team IDの本番値差し替え
