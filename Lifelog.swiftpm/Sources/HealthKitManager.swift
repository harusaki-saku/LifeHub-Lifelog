import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var lastSyncedAt: Date?
    @Published var lastSyncError: String?

    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private let workoutType = HKObjectType.workoutType()

    private var readTypes: Set<HKSampleType> {
        [sleepType, workoutType]
    }

    // MARK: - 権限リクエスト（段階的要求: MVPはsleep + workoutのみ。
    // 拡張フェーズで心拍・HRV等を追加する際はここに型を足して再度呼び出す）

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastSyncError = "このデバイスはHealthKitに対応していません"
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            startObserving()
        } catch {
            lastSyncError = "HealthKit権限リクエストに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - バックグラウンド同期（HKObserverQuery + Background Delivery）

    func startObserving() {
        for type in readTypes {
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { [weak self] success, error in
                if let error {
                    Task { @MainActor in
                        self?.lastSyncError = "Background Delivery設定に失敗: \(error.localizedDescription)"
                    }
                }
            }

            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
                guard let self else {
                    completionHandler()
                    return
                }
                Task {
                    await self.syncNewSamples(for: type)
                    completionHandler()
                }
            }
            healthStore.execute(observer)
        }
    }

    /// アプリを開いた時の手動同期（デバッグ・初回バックフィル確認用）
    func syncNow() async {
        for type in readTypes {
            await syncNewSamples(for: type)
        }
    }

    // MARK: - 増分同期
    // HKAnchoredObjectQueryでアンカーを永続化し、同じサンプルを再取得しないようにする。
    // 初回（アンカー未保存時）のみ initialBackfillDays 分を遡って取得する。

    private func syncNewSamples(for type: HKSampleType) async {
        let anchor = loadAnchor(for: type)
        let predicate: NSPredicate? = anchor == nil
            ? HKQuery.predicateForSamples(
                withStart: Calendar.current.date(byAdding: .day, value: -Config.initialBackfillDays, to: Date()),
                end: nil,
                options: .strictStartDate
            )
            : nil

        do {
            let (samples, newAnchor) = try await anchoredQuery(type: type, predicate: predicate, anchor: anchor)
            saveAnchor(newAnchor, for: type)

            guard !samples.isEmpty else { return }

            let payloads = samples.compactMap { makePayload(from: $0, type: type) }
            guard !payloads.isEmpty else { return }

            try await LifelogAPIClient.shared.postRawSamples(payloads)

            lastSyncedAt = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = "同期に失敗しました: \(error.localizedDescription)"
        }
    }

    private func anchoredQuery(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?
    ) async throws -> ([HKSample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - サンプル → 送信用ペイロード変換
    // 重複排除（ソース優先順位）と日付境界（起床日基準）の判定はサーバー側で行うため、
    // ここでは生データ（ソース情報込み）をそのまま送るだけに留める。

    /// HKCategoryValueSleepAnalysis → サーバー側dedupe.tsが理解する文字列（手法C・レビュー指摘）。
    /// inBedとasleep*/awakeは同じ時間帯に重複して記録されるため、サーバー側でinBed優先の
    /// 集計対象フィルタをかける際にこの値を使う。
    private static let sleepCategoryMap: [HKCategoryValueSleepAnalysis: String] = [
        .inBed: "inBed",
        .asleepUnspecified: "asleepUnspecified",
        .asleepCore: "asleepCore",
        .asleepDeep: "asleepDeep",
        .asleepREM: "asleepREM",
        .awake: "awake",
    ]

    private func makePayload(from sample: HKSample, type: HKSampleType) -> RawSamplePayload? {
        let source = sample.sourceRevision.source

        if type == sleepType, let categorySample = sample as? HKCategorySample {
            let sleepCategory = HKCategoryValueSleepAnalysis(rawValue: categorySample.value)
                .flatMap { Self.sleepCategoryMap[$0] }

            return RawSamplePayload(
                sampleId: categorySample.uuid.uuidString,
                logType: "sleep",
                startDate: categorySample.startDate,
                endDate: categorySample.endDate,
                value: categorySample.endDate.timeIntervalSince(categorySample.startDate),
                unit: "seconds",
                sourceId: source.bundleIdentifier,
                sourceName: source.name,
                timeZoneIdentifier: TimeZone.current.identifier,
                sleepCategory: sleepCategory
            )
        }

        if type == workoutType, let workout = sample as? HKWorkout {
            return RawSamplePayload(
                sampleId: workout.uuid.uuidString,
                logType: "exercise",
                startDate: workout.startDate,
                endDate: workout.endDate,
                value: workout.duration,
                unit: "seconds",
                sourceId: source.bundleIdentifier,
                sourceName: source.name,
                timeZoneIdentifier: TimeZone.current.identifier,
                sleepCategory: nil
            )
        }

        return nil
    }

    // MARK: - アンカー永続化（UserDefaults。端末紐付けのみで機密情報ではないためKeychain不要）

    private func anchorKey(for type: HKSampleType) -> String {
        "healthkit.anchor.\(type.identifier)"
    }

    private func loadAnchor(for type: HKSampleType) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey(for: type)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor?, for type: HKSampleType) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        else { return }
        UserDefaults.standard.set(data, forKey: anchorKey(for: type))
    }
}
