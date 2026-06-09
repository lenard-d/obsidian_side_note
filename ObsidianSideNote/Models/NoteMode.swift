import Foundation

enum NoteMode {
    case appendDaily
    case newNote
    case editVaultFile
    case settings
    case setup

    var title: String {
        switch self {
        case .appendDaily:
            return "Daily Note"
        case .newNote:
            return "Create New Note"
        case .editVaultFile:
            return "Edit Vault File"
        case .settings:
            return "Settings"
        case .setup:
            return "Setup"
        }
    }

    var draftTextKey: String {
        switch self {
        case .appendDaily:
            return "draft.appendDaily.text"
        case .newNote:
            return "draft.newNote.text"
        case .editVaultFile:
            return "draft.editVaultFile.text"
        case .settings, .setup:
            return ""
        }
    }

    var draftTitleKey: String {
        switch self {
        case .newNote:
            return "draft.newNote.title"
        case .editVaultFile:
            return "draft.editVaultFile.path"
        case .appendDaily, .settings, .setup:
            return ""
        }
    }

    var usesTextEditor: Bool {
        switch self {
        case .appendDaily, .newNote, .editVaultFile:
            return true
        case .settings, .setup:
            return false
        }
    }

    var startsWithTitleFocus: Bool {
        self == .newNote
    }

    var startsWithEditorFocus: Bool {
        switch self {
        case .appendDaily, .editVaultFile:
            return true
        case .newNote, .settings, .setup:
            return false
        }
    }
}

extension NoteMode: Equatable {}
