import SwiftUI

struct GarminImportView: View {
    var onComplete: (() -> Void)? = nil
    /// When set, GPX is saved to this project instead of creating a new one.
    var targetProject: Project? = nil

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
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(.blue)
                        Text("Garmin Connect").font(.title2.bold())
                        Text("Sign in to import GPX from your activities.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Text("Signing in…")
                            Spacer()
                        }
                    } else {
                        Text("Sign In").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            }

            Section {
                Text("Note: Multi-factor authentication must be disabled for direct sign-in.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif
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
            } else if activities.isEmpty {
                ContentUnavailableView(
                    "No Cycling Activities",
                    systemImage: "bicycle",
                    description: Text("No cycling activities found in your Garmin Connect account")
                )
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
        .task { await loadActivities() }
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
            if (error as? URLError)?.code != .cancelled {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func importActivity(_ activity: GarminActivity) async {
        isImporting = true; error = nil
        do {
            let project: Project
            if let existing = targetProject {
                project = existing
            } else {
                guard let root = GlobalSettings.shared.projectsRoot else {
                    error = "Set a Projects Root folder in Settings before importing"
                    isImporting = false; return
                }
                let folderName = activity.suggestedProjectName
                let folderURL  = root.appending(path: folderName)
                project = Project(name: folderName, folderURL: folderURL)
                try ProjectFileManager.createDirectoryStructure(for: project)
            }

            try await GarminClient().downloadGPX(activityID: activity.activityId, to: project.gpxFile)
            if targetProject == nil { store.add(project) }
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isImporting = false
    }
}
