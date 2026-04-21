import SwiftUI

struct StravaImportView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var activities: [[String: Any]] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if StravaAuth.shared.isAuthenticated {
                    activityList
                } else {
                    signInPrompt
                }
            }
            .navigationTitle("Strava Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.cycling").font(.system(size: 60)).foregroundStyle(.orange)
            Text("Connect Strava to import GPX\nfrom your activities")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Sign In with Strava") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .padding()
    }

    @ViewBuilder
    private var activityList: some View {
        if activities.isEmpty {
            ProgressView("Loading activities...")
                .task { await loadActivities() }
        } else {
            List(activities.indices, id: \.self) { i in
                let a = activities[i]
                Button {
                    Task { await importActivity(a) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(a["name"] as? String ?? "Activity").font(.headline)
                        Text(a["start_date_local"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func authenticate() async {
        isAuthenticating = true
        do {
            _ = try await StravaAuth.shared.authenticate()
            await loadActivities()
        } catch {
            self.error = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func loadActivities() async {
        do {
            activities = try await StravaClient().recentActivities()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importActivity(_ activity: [String: Any]) async {
        // TODO: Phase 5 — create project folder, download GPX, open in ProjectDetailView
        dismiss()
    }
}
