import Foundation
import Defaults

struct NewNotePreferences {
    static let resumeIntervalMinutesKey = "newNote.resumeIntervalMinutes"
    static let draftFilePathKey = "draft.newNote.filePath"
    static let sessionStartedAtKey = "draft.newNote.sessionStartedAt"
    static let useObsidianNewNoteFolderKey = "newNote.useObsidianFolder"
    static let folderPathKey = "newNote.folderPath"

    static let allowedResumeIntervals = [1, 3, 5, 10, 15]

    static var useObsidianNewNoteFolder: Bool {
        guard UserDefaults.standard.object(forKey: useObsidianNewNoteFolderKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: useObsidianNewNoteFolderKey)
    }

    static var folderPath: String {
        UserDefaults.standard.string(forKey: folderPathKey) ?? ""
    }

    static var resumeIntervalMinutes: Int {
        migrateResumeIntervalIfNeeded()
        let savedValue = Defaults[.newNoteResumeIntervalMinutes]
        return allowedResumeIntervals.contains(savedValue) ? savedValue : 5
    }

    static func setUseObsidianNewNoteFolder(_ useObsidianFolder: Bool) {
        UserDefaults.standard.set(useObsidianFolder, forKey: useObsidianNewNoteFolderKey)
        AppConfigStore.saveNewNoteFolderPreferences(
            useObsidianFolder: useObsidianFolder,
            folderPath: folderPath
        )
    }

    static func setFolderPath(_ path: String) {
        let normalizedPath = normalizedFolderPath(path)
        UserDefaults.standard.set(normalizedPath, forKey: folderPathKey)
        AppConfigStore.saveNewNoteFolderPreferences(
            useObsidianFolder: useObsidianNewNoteFolder,
            folderPath: normalizedPath
        )
    }

    static func setResumeIntervalMinutes(_ minutes: Int) {
        guard allowedResumeIntervals.contains(minutes) else { return }
        Defaults[.newNoteResumeIntervalMinutes] = minutes
        AppConfigStore.saveNewNoteResumeInterval(minutes)
    }

    static func startSession(now: Date = Date()) {
        touchSession(now: now)
    }

    static func touchSession(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: sessionStartedAtKey)
    }

    static func shouldResumeVisibleSession(now: Date = Date()) -> Bool {
        guard let startedAt = UserDefaults.standard.object(forKey: sessionStartedAtKey) as? Date else {
            return false
        }

        let interval = TimeInterval(resumeIntervalMinutes * 60)
        return now.timeIntervalSince(startedAt) <= interval
    }

    static func clearDraft() {
        UserDefaults.standard.removeObject(forKey: NoteMode.newNote.draftTextKey)
        UserDefaults.standard.removeObject(forKey: NoteMode.newNote.draftTitleKey)
        UserDefaults.standard.removeObject(forKey: draftFilePathKey)
        UserDefaults.standard.removeObject(forKey: sessionStartedAtKey)
    }

    private static func migrateResumeIntervalIfNeeded() {
        guard UserDefaults.standard.object(forKey: resumeIntervalMinutesKey) != nil else {
            return
        }

        let savedValue = UserDefaults.standard.integer(forKey: resumeIntervalMinutesKey)
        if allowedResumeIntervals.contains(savedValue) {
            Defaults[.newNoteResumeIntervalMinutes] = savedValue
        }
        UserDefaults.standard.removeObject(forKey: resumeIntervalMinutesKey)
    }

    private static func normalizedFolderPath(_ path: String) -> String {
        var normalizedPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }

        return normalizedPath == "." ? "" : normalizedPath
    }
}

extension Defaults.Keys {
    static let newNoteResumeIntervalMinutes = Key<Int>("newNoteResumeIntervalMinutes", default: 5)
}
