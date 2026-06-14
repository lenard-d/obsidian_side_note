import Darwin
import Foundation

final class VaultNoteFileMonitor {
    typealias ChangeHandler = () -> Void

    private let eventQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let notificationDelay: TimeInterval
    private var source: DispatchSourceFileSystemObject?
    private var monitoredURL: URL?
    private var onChange: ChangeHandler?
    private var pendingNotification: DispatchWorkItem?
    private var pendingReopen: DispatchWorkItem?

    init(
        eventQueue: DispatchQueue = DispatchQueue(label: "live.lukesmith.ObsidianSideNote.note-file-monitor", qos: .utility),
        callbackQueue: DispatchQueue = .main,
        notificationDelay: TimeInterval = 0.08
    ) {
        self.eventQueue = eventQueue
        self.callbackQueue = callbackQueue
        self.notificationDelay = notificationDelay
    }

    func start(url: URL, onChange: @escaping ChangeHandler) {
        stop()
        monitoredURL = url
        self.onChange = onChange
        eventQueue.async { [weak self] in
            self?.openSourceIfNeeded()
        }
    }

    func stop() {
        pendingNotification?.cancel()
        pendingNotification = nil
        pendingReopen?.cancel()
        pendingReopen = nil
        closeSource()
        monitoredURL = nil
        onChange = nil
    }

    private func openSourceIfNeeded() {
        guard source == nil, let monitoredURL else { return }

        let descriptor = open(monitoredURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleReopen()
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: eventQueue
        )
        newSource.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            self.handle(events: source.data)
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        source = newSource
        newSource.resume()
    }

    private func handle(events: DispatchSource.FileSystemEvent) {
        scheduleNotification()

        if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
            closeSource()
            scheduleReopen()
        }
    }

    private func closeSource() {
        source?.cancel()
        source = nil
    }

    private func scheduleNotification() {
        pendingNotification?.cancel()
        let notification = DispatchWorkItem { [weak self] in
            guard let self, let onChange else { return }
            callbackQueue.async(execute: onChange)
        }
        pendingNotification = notification
        eventQueue.asyncAfter(deadline: .now() + notificationDelay, execute: notification)
    }

    private func scheduleReopen() {
        pendingReopen?.cancel()
        let reopen = DispatchWorkItem { [weak self] in
            self?.openSourceIfNeeded()
        }
        pendingReopen = reopen
        eventQueue.asyncAfter(deadline: .now() + notificationDelay, execute: reopen)
    }
}
