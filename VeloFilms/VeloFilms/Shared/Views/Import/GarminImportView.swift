import SwiftUI

struct GarminImportView: View {
    var onComplete: (() -> Void)? = nil

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = GarminAuth.shared.savedEmail ?? ""
    @State private var password: String = ""
    @State private var activities: [GarminActivity] = []
    @State private var isSigningIn  = false
    @State private var isLoading    = false
    @State private var isImporting  = false
    @State private var error: String?

    private var auth: GarminAuth { GarminAuth.shared }

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAuthenticated {
                    activityList
                } else {
                    loginForm
                }
            }
            .navigationTitle("Garmin Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if auth.isAuthenticated {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Sign Out") {
                            auth.signOut()
                            activities = []
                        }
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
        .task { await auth.checkSession() }
    }

    // MARK: - Login form

    private var loginForm: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.circle").font(.system(size: 60)).foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Garmin Connect").font(.title2.bold())
                    Text("Sign in with your Garmin Connect credentials to import GPX from your activities.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email").font(.caption).foregroundStyle(.secondary)
                        TextField("garmin@example.com", text: $email)
                            .textContentType(.emailAddress)
#if os(macOS)
                            .textFieldStyle(.roundedBorder)
#endif
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.caption).foregroundStyle(.secondary)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
#if os(macOS)
                            .textFieldStyle(.roundedBorder)
#endif
                    }
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.caption).multilineTextAlignment(.center)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        HStack { ProgressView().scaleEffect(0.8); Text("Signing in…") }
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isSigningIn)

                Text("Note: Multi-factor authentication must be disabled for direct sign-in.")
                    .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    // MARK: - Activity list

    @ViewBuilder
    private var activityList: some View {
        VStack(spacing: 0) {
            if auth.isAuthenticated {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Signed in as **\(auth.displayName)**")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal).padding(.top, 8)
            }

            if isLoading && activities.isEmpty {
                ProgressView("Loading activities...").padding()
                    .task { await loadActivities() }
            } else if activities.isEmpty {
                ContentUnavailableView(
                    "No Cycling Activities",
                    systemImage: "bicycle",
                    description: Text("No cycling activities found in your Garmin Connect account")
                )
                .task { await loadActivities() }
            } else {
                List(activities) { activity in
                    Button { Task { await importActivity(activity) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.activityName).font(.headline)
                                Text("\(activity.displayDate)  ·  \(activity.distanceKm)  ·  \(activity.durationStr)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isImporting {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(isImporting)
                }
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal).padding(.bottom, 8)
            }
        }
    }

    // MARK: - Actions

    private func signIn() async {
        isSigningIn = true; error = nil
        do {
            try await auth.signIn(email: email, password: password)
            password = ""   // clear after use
            await loadActivities()
        } catch {
            self.error = error.localizedDescription
        }
        isSigningIn = false
    }

    private func loadActivities() async {
        isLoading = true; error = nil
        do {
            let all = try await GarminClient().recentActivities()
            activities = all.filter { $0.isCycling }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func importActivity(_ activity: GarminActivity) async {
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
            try await GarminClient().downloadGPX(activityID: activity.activityId, to: gpxURL)
            store.add(project)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isImporting = false
    }
}
