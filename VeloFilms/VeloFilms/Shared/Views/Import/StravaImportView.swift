import SwiftUI

struct StravaImportView: View {
    var onComplete: (() -> Void)? = nil

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var activities: [StravaActivity] = []
    @State private var isLoading = false
    @State private var isImporting = false
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
                if StravaAuth.shared.isAuthenticated {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Sign Out") {
                            StravaAuth.shared.signOut()
                            activities = []
                        }
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
    }

    private var signInPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "bicycle").font(.system(size: 60)).foregroundStyle(.orange)
            Text("Connect Strava to import GPX from your activities")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Sign In with Strava") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
            if isLoading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .padding()
    }

    @ViewBuilder
    private var activityList: some View {
        if isLoading && activities.isEmpty {
            ProgressView("Loading activities...").task { await loadActivities() }
        } else if activities.isEmpty {
            ContentUnavailableView(
                "No Cycling Activities",
                systemImage: "bicycle",
                description: Text("No rides found in your recent Strava activities")
            )
            .task { await loadActivities() }
        } else {
            List(activities) { activity in
                Button { Task { await importActivity(activity) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name).font(.headline)
                            Text("\(activity.displayDate)  ·  \(activity.distanceKm)  ·  \(activity.durationStr)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isImporting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle").foregroundStyle(.orange)
                        }
                    }
                }
                .disabled(isImporting)
            }
        }
        if let error {
            Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal)
        }
    }

    private func authenticate() async {
        isLoading = true; error = nil
        do {
            _ = try await StravaAuth.shared.authenticate()
            await loadActivities()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadActivities() async {
        isLoading = true; error = nil
        do {
            let all = try await StravaClient().recentActivities()
            activities = all.filter { $0.isCycling }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func importActivity(_ activity: StravaActivity) async {
        guard let root = GlobalSettings.shared.projectsRoot else {
            error = "Set a Projects Root folder in Settings before importing"
            return
        }
        isImporting = true; error = nil
        do {
            let folderName = activity.suggestedProjectName
            let folderURL  = root.appending(path: folderName)
            let project    = Project(name: folderName, folderURL: folderURL)
            try ProjectFileManager.createDirectoryStructure(for: project)

            let gpxURL = project.workingDir.appending(path: "activity.gpx")
            let startDate = ISO8601DateFormatter().date(from: activity.startDateLocal) ?? Date()
            try await StravaClient().downloadGPX(
                activityID:   activity.id,
                startDate:    startDate,
                activityName: activity.name,
                to:           gpxURL
            )
            store.add(project)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isImporting = false
    }
}
