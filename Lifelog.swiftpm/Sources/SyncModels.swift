import Foundation

/// HealthKitの生サンプルをそのままAPIへ送るペイロード。
///
/// 重複排除（ソース優先順位: Apple Watch > iPhone本体 > サードパーティ）と
/// 日付境界（起床日基準）の解決はサーバー側（lifelog-api-stack）で行う設計のため、
/// クライアント側では加工・集計をせずソース情報込みでそのまま送信する。
/// これにより将来「ユーザーが値を選び直す」UIを、サーバーに保存した生データから復元できる。
struct RawSamplePayload: Codable {
    let sampleId: String
    /// "sleep" | "exercise"
    let logType: String
    let startDate: Date
    let endDate: Date
    /// sleep/exerciseどちらも「秒数（duration = endDate - startDate）」で統一。
    let value: Double
    let unit: String
    let sourceId: String
    let sourceName: String
    /// 日付バケット計算（起床日基準）をサーバー側で行うためのタイムゾーン。例: "Asia/Tokyo"
    let timeZoneIdentifier: String
    /// logType=="sleep"のときのみ設定。inBed/asleep*/awakeの区別。
    /// サーバー側（dedupe.ts）がinBedを優先的な集計対象にするために使う（レビュー指摘・手法C）。
    let sleepCategory: String?
}

struct RawSamplesRequest: Codable {
    let samples: [RawSamplePayload]
}
