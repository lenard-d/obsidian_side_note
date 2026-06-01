import SwiftUI
import AppKit

struct SetupView: View {
    @Binding var vaultName: String
    @Binding var vaultPath: String
    let closeWindow: () -> Void
    @State private var resumeIntervalMinutes = NewNotePreferences.resumeIntervalMinutes

    private var hasVault: Bool {
        !vaultPath.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introSection
                    prerequisitesSection
                    vaultSection
                    shortcutsSection
                    newNoteSection
                }
                .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))

            Divider()
            footer
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Obsidian Side Note")
                .font(.system(size: 13, weight: .semibold))
            WindowDragHandle()
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
            Button(action: closeWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick setup")
                .font(.system(size: 18, weight: .semibold))
            Text("Capture quick notes, append to your daily note, and edit Markdown files in your vault without switching context.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var prerequisitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prerequisites")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            setupStep("Install Obsidian and create or open your vault.")
            setupStep("In Obsidian, open Settings -> Community plugins.")
            setupStep("Turn off Restricted mode, search for Advanced URI, then install and enable it.")
            setupStep("Enable the Daily notes core plugin if you want Append to Daily Note.")
        }
    }

    private func setupStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 14, height: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vault folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hasVault ? vaultName : "No vault selected")
                        .font(.system(size: 12, weight: .medium))
                    Text(hasVault ? vaultPath : "Choose the local folder that contains your Obsidian Markdown files.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(hasVault ? "Change..." : "Choose...") {
                    chooseVaultFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard shortcuts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(ShortcutAction.allCases) { action in
                KeyboardShortcutRow(action: action)
            }
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
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(hasVault ? "Ready to use." : "Select a vault folder to finish setup.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Done") {
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasVault)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func chooseVaultFolder() {
        guard let url = VaultStore.chooseVaultFolder(message: "Choose your Obsidian vault folder to finish setup.") else { return }
        vaultName = url.lastPathComponent
        vaultPath = url.path
    }
}
