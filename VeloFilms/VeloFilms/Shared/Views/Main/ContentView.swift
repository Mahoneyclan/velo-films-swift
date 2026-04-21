import SwiftUI

struct ContentView: View {
    @Environment(ProjectStore.self) private var projectStore

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let project = projectStore.selected {
                ProjectDetailView(project: project)
            } else {
                Text("Select a project")
                    .foregroundStyle(.secondary)
            }
        }
#else
        NavigationStack {
            ProjectListView()
        }
#endif
    }
}
