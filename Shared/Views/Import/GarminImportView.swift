import SwiftUI

struct GarminImportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle").font(.system(size: 60)).foregroundStyle(.blue)
                Text("Garmin Connect import\nnot yet implemented")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("You can manually export a GPX from Garmin Connect\nand place it in the project's working/ folder.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("Garmin Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
