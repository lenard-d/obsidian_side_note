import Foundation

enum ShortcutAction: String, CaseIterable, Identifiable {
    case appendDaily
    case newNote
    case editVaultFile
    case settings

    var id: String { rawValue }

    static let globalActions: [ShortcutAction] = [
        .appendDaily,
        .newNote,
        .editVaultFile
    ]

    var hotKeyID: Int {
        switch self {
        case .appendDaily:
            return 1
        case .newNote:
            return 2
        case .editVaultFile:
            return 3
        case .settings:
            return 4
        }
    }

    init?(hotKeyID: Int) {
        switch hotKeyID {
        case ShortcutAction.appendDaily.hotKeyID:
            self = .appendDaily
        case ShortcutAction.newNote.hotKeyID:
            self = .newNote
        case ShortcutAction.editVaultFile.hotKeyID:
            self = .editVaultFile
        case ShortcutAction.settings.hotKeyID:
            self = .settings
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .appendDaily:
            return "Append to Daily Note"
        case .newNote:
            return "Create New Note"
        case .editVaultFile:
            return "Edit Vault File"
        case .settings:
            return "Settings"
        }
    }

    var preferenceKey: String {
        "shortcut.\(rawValue)"
    }

    var modifierPreferenceKey: String {
        "shortcut.\(rawValue).modifiers"
    }

    var defaultKey: String {
        switch self {
        case .appendDaily:
            return "d"
        case .newNote:
            return "n"
        case .editVaultFile:
            return "e"
        case .settings:
            return ","
        }
    }

    var shortcut: ShortcutDefinition {
        ShortcutPreference.definition(for: self)
    }

    var isGlobal: Bool {
        Self.globalActions.contains(self)
    }
}
