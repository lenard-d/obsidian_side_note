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
            return "Append to Daily Note"
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
}

extension NoteMode: Equatable {}
