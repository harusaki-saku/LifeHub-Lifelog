import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("認証") {
                    if authManager.isSignedIn {
                        Label("ログイン済み", systemImage: "checkmark.circle.fill")
                    } else {
                        Button("Showlaboアカウントでログイン") {
                            Task { try? await authManager.signIn() }
                        }
                    }
                }

                Section("HealthKit") {
                    if healthKitManager.isAuthorized {
                        Label("連携済み", systemImage: "checkmark.circle.fill")
                    } else {
                        Button("HealthKitの利用を許可") {
                            Task { await healthKitManager.requestAuthorization() }
                        }
                    }

                    Button("今すぐ同期") {
                        Task { await healthKitManager.syncNow() }
                    }
                    .disabled(!healthKitManager.isAuthorized)

                    if let lastSyncedAt = healthKitManager.lastSyncedAt {
                        Text("最終同期: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }

                    if let error = healthKitManager.lastSyncError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Lifelog")
        }
    }
}
