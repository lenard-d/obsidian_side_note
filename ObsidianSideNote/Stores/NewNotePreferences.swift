import Foundation

struct NewNotePreferences {
    static let resumeIntervalMinutesKey = "newNote.resumeIntervalMinutes"
    static let draftFilePathKey = "draft.newNote.filePath"
    static let sessionStartedAtKey = "draft.newNote.sessionStartedAt"

    static let allowedResumeIntervals = [1, 3, 5, 10, 15]

    static var resumeIntervalMinutes: Int {
        let savedValue = UserDefaults.standard.integer(forKey: resumeIntervalMinutesKey)
        return allowedResumeIntervals.contains(savedValue) ? savedValue : 5
    }

    static func setResumeIntervalMinutes(_ minutes: Int) {
        guard allowedResumeIntervals.contains(minutes) else { return }
        UserDefaults.standard.set(minutes, forKey: resumeIntervalMinutesKey)
    }

    static func startSession(now: Date = Date()) {
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
}
