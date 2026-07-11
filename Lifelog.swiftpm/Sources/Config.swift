import Foundation

enum Config {
    /// lifelog-api-stack (LifehubLifelogApiStack) のエンドポイント
    static let apiBaseURL = URL(string: "https://qymuevmbo1.execute-api.ap-northeast-1.amazonaws.com/prod")!

    /// auth.showlabo.com のCognito Hosted UIドメイン（brand.mdより。全サービス共通）
    static let cognitoDomain = "auth.showlabo.com"

    /// Cognito App Client: showlabo-lifelog-ios (ShowlaboAuthCognito stack)
    static let cognitoClientId = "55clmjgm8e6qkre2fvdqdq5rf7"

    /// Package.swiftのbundleIdentifierと揃えること
    static let cognitoRedirectUri = "com.showlabo.lifehub.lifelog://auth/callback"

    /// 初回同期時に遡って取得するHealthKitデータの日数
    /// （ideaLifelog.md §0-1で30日と決定：曜日パターンが約4周し傾向が見える／同期負荷も軽微）
    static let initialBackfillDays = 30
}
