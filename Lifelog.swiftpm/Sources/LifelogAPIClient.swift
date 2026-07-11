import Foundation

enum LifelogAPIError: Error {
    case notAuthenticated
    case invalidResponse
}

final class LifelogAPIClient {
    static let shared = LifelogAPIClient()

    private init() {}

    /// lifelog-api-stackの POST /logs/raw に生サンプルをまとめて送信する。
    /// 重複排除・日付境界の解決はサーバー側Lambdaで行う（ideaLifelog.md §0-2）。
    func postRawSamples(_ samples: [RawSamplePayload]) async throws {
        guard let idToken = try await AuthManager.shared.currentIdToken() else {
            throw LifelogAPIError.notAuthenticated
        }

        var request = URLRequest(url: Config.apiBaseURL.appendingPathComponent("logs/raw"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(RawSamplesRequest(samples: samples))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw LifelogAPIError.invalidResponse
        }
    }
}
