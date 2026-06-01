import SwiftUI
import AppKit

struct SettingsView: View {
    @Binding var vaultName: String
    @Binding var vaultPath: String
    let closeWindow: () -> Void
    @State private var resumeIntervalMinutes = NewNotePreferences.resumeIntervalMinutes

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                WindowDragHandle()
                    .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
                Button(action: closeWindow) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    vaultSection
                    Divider()
                    newNoteSection
                    Divider()
                    shortcutsSection
                }
                .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Obsidian Vault")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vaultName.isEmpty ? "No vault selected" : vaultName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text(vaultPath.isEmpty ? "Choose a folder from Finder" : vaultPath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Choose...") {
                    chooseVaultFolder()
                }
                .buttonStyle(.bordered)
            }

            Text("Pick the local folder that contains your Obsidian Markdown files.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var newNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("Resume interval", selection: $resumeIntervalMinutes) {
                ForEach(NewNotePreferences.allowedResumeIntervals, id: \.self) { minutes in
                    Text("\(minutes)m").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: resumeIntervalMinutes) { oldValue, newValue in
                NewNotePreferences.setResumeIntervalMinutes(newValue)
            }

            Text("Within this window, reopening New Note keeps the current draft unless you use the shortcut.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(ShortcutAction.allCases) { action in
                KeyboardShortcutRow(action: action)
            }
        }
    }

    private func chooseVaultFolder() {
        guard let url = VaultStore.chooseVaultFolder() else { return }
        vaultName = url.lastPathComponent
        vaultPath = url.path
    }
}
