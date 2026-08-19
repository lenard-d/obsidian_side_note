import AppKit
import SwiftUI

@MainActor
final class LinkPreviewController {
    private struct SourceKey: Hashable {
        let windowID: ObjectIdentifier
        let sessionID: String
    }

    private struct PreviewNode {
        let window: LinkPreviewPanel
        let sourceKey: SourceKey
        let parentWindowID: ObjectIdentifier?
    }

    private let hoverDelayProvider: () -> TimeInterval
    private let dismissalDelay: TimeInterval
    private var pendingOpen: [SourceKey: DispatchWorkItem] = [:]
    private var pendingDismissal: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var nodes: [ObjectIdentifier: PreviewNode] = [:]

    init(
        hoverDelayProvider: (() -> TimeInterval)? = nil,
        dismissalDelay: TimeInterval = 0.18
    ) {
        self.hoverDelayProvider = hoverDelayProvider ?? { LinkPreviewPreferences.hoverDelaySeconds }
        self.dismissalDelay = dismissalDelay
    }

    var visibleWindows: [NSWindow] {
        nodes.values.map(\.window).filter(\.isVisible)
    }

    func handle(_ event: LinkPreviewHoverEvent, from sourceWindow: NSWindow?) {
        guard let sourceWindow else { return }
        let key = SourceKey(windowID: ObjectIdentifier(sourceWindow), sessionID: event.sessionID)

        switch event.phase {
        case .entered:
            pendingOpen.removeValue(forKey: key)?.cancel()
            if let existing = nodes.values.first(where: { $0.sourceKey == key }) {
                cancelDismissal(for: existing.window)
                return
            }

            let workItem = DispatchWorkItem { [weak self, weak sourceWindow] in
                guard let self, let sourceWindow else { return }
                self.pendingOpen.removeValue(forKey: key)
                self.showPreview(for: event, key: key, sourceWindow: sourceWindow)
            }
            pendingOpen[key] = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + max(0, hoverDelayProvider()),
                execute: workItem
            )

        case .exited:
            pendingOpen.removeValue(forKey: key)?.cancel()
            guard let node = nodes.values.first(where: { $0.sourceKey == key }) else { return }
            scheduleDismissal(of: node.window)
        }
    }

    func pointerEntered(_ window: NSWindow) {
        cancelDismissalForNodeAndAncestors(startingAt: ObjectIdentifier(window))
    }

    func pointerExited(_ window: NSWindow) {
        scheduleDismissal(of: window)
    }

    func sourceWindowClosed(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        pendingOpen
            .filter { $0.key.windowID == windowID }
            .forEach { key, workItem in
                workItem.cancel()
                pendingOpen.removeValue(forKey: key)
            }
        nodes.values
            .filter { $0.sourceKey.windowID == windowID }
            .forEach { closeSubtree(startingAt: ObjectIdentifier($0.window)) }
    }

    private func showPreview(
        for event: LinkPreviewHoverEvent,
        key: SourceKey,
        sourceWindow: NSWindow
    ) {
        let note: VaultNote?
        switch event.kind {
        case .wiki:
            note = VaultStore.note(forWikiLink: event.target)
        case .markdown:
            note = VaultStore.note(forMarkdownLink: event.target)
        }
        guard let note, let markdown = try? VaultStore.readNote(note) else { return }

        nodes.values
            .filter { $0.sourceKey.windowID == key.windowID && $0.sourceKey != key }
            .forEach { closeSubtree(startingAt: ObjectIdentifier($0.window)) }

        let size = NSSize(width: 390, height: 460)
        let frame = Self.previewFrame(
            anchoredTo: event.anchorScreenRect,
            size: size,
            sourceWindow: sourceWindow
        )
        let panel = LinkPreviewPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = note.title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isRestorable = false

        let hostingView = NSHostingView(
            rootView: LinkPreviewContentView(
                note: note,
                markdown: markdown,
                linkPreviewHover: { [weak self, weak panel] hover in
                    guard let panel else { return }
                    self?.handle(hover, from: panel)
                }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]

        let trackingView = LinkPreviewTrackingView(frame: hostingView.frame)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.addSubview(hostingView)
        trackingView.onPointerEntered = { [weak self, weak panel] in
            guard let panel else { return }
            self?.pointerEntered(panel)
        }
        trackingView.onPointerExited = { [weak self, weak panel] in
            guard let panel else { return }
            self?.pointerExited(panel)
        }
        panel.contentView = trackingView

        let parentWindowID = nodes[key.windowID] == nil ? nil : key.windowID
        nodes[ObjectIdentifier(panel)] = PreviewNode(
            window: panel,
            sourceKey: key,
            parentWindowID: parentWindowID
        )
        panel.orderFrontRegardless()
    }

    private func scheduleDismissal(of window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        pendingDismissal.removeValue(forKey: windowID)?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self, window != nil else { return }
            self.pendingDismissal.removeValue(forKey: windowID)
            self.closeSubtree(startingAt: windowID)
        }
        pendingDismissal[windowID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissalDelay, execute: workItem)
    }

    private func cancelDismissal(for window: NSWindow) {
        pendingDismissal.removeValue(forKey: ObjectIdentifier(window))?.cancel()
    }

    private func cancelDismissalForNodeAndAncestors(startingAt windowID: ObjectIdentifier) {
        var currentWindowID: ObjectIdentifier? = windowID
        while let id = currentWindowID, let node = nodes[id] {
            cancelDismissal(for: node.window)
            currentWindowID = node.parentWindowID
        }
    }

    private func closeSubtree(startingAt windowID: ObjectIdentifier) {
        let childIDs = nodes
            .filter { $0.value.parentWindowID == windowID }
            .map(\.key)
        childIDs.forEach { closeSubtree(startingAt: $0) }

        pendingDismissal.removeValue(forKey: windowID)?.cancel()
        guard let node = nodes.removeValue(forKey: windowID) else { return }
        pendingOpen
            .filter { $0.key.windowID == windowID }
            .forEach { key, workItem in
                workItem.cancel()
                pendingOpen.removeValue(forKey: key)
            }
        node.window.orderOut(nil)
        node.window.close()
    }

    private static func previewFrame(
        anchoredTo anchor: NSRect,
        size: NSSize,
        sourceWindow: NSWindow
    ) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchor) })
            ?? sourceWindow.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 10
        let belowY = anchor.minY - gap - size.height
        let aboveY = anchor.maxY + gap
        let y = belowY >= visibleFrame.minY
            ? belowY
            : min(aboveY, visibleFrame.maxY - size.height)
        let proposedX = anchor.midX - 28
        let x = min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - size.width)
        return NSRect(x: x, y: max(y, visibleFrame.minY), width: size.width, height: size.height)
    }
}

private final class LinkPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LinkPreviewTrackingView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }
}

private struct LinkPreviewContentView: View {
    let note: VaultNote
    let linkPreviewHover: (LinkPreviewHoverEvent) -> Void
    @State private var markdown: String
    @State private var focusRequestID = 0
    @State private var cursorEndRequestID = 0
    @FocusState private var isEditorFocused: Bool
    @StateObject private var commandDispatcher = MarkdownEditorCommandDispatcher()

    init(
        note: VaultNote,
        markdown: String,
        linkPreviewHover: @escaping (LinkPreviewHoverEvent) -> Void
    ) {
        self.note = note
        self.linkPreviewHover = linkPreviewHover
        _markdown = State(initialValue: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("View Vault File")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(note.title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            RichMarkdownEditorView(
                text: $markdown,
                isFocused: $isEditorFocused,
                focusRequestID: $focusRequestID,
                cursorEndRequestID: $cursorEndRequestID,
                commandDispatcher: commandDispatcher,
                insertMedia: { _ in },
                didInsertMedia: {},
                didFailMediaImport: { _ in },
                openWikiLink: { _, _ in },
                openMarkdownLink: { _, _ in },
                isReadOnly: true,
                linkPreviewHover: linkPreviewHover
            )
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of \(note.title)")
    }
}
