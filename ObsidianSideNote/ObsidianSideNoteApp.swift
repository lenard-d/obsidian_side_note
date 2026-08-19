//
//  ObsidianSideNoteApp.swift
//  ObsidianSideNote
//
//  Created by Luke Smith on 11/27/25.
//

import SwiftUI
import AppKit
import OSLog

@main
struct ObsidianSideNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var window: NSWindow?
    var menu: NSMenu?
    private var appendMenuItem: NSMenuItem?
    private var newNoteMenuItem: NSMenuItem?
    private var editFileMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var hotKeyManager: GlobalHotKeyManager?
    private var managedWindows: [ObjectIdentifier: (window: NSWindow, mode: NoteMode)] = [:]
    private lazy var linkPreviewController = LinkPreviewController()
    private var localShortcutMonitor: Any?
    var externalURLOpener: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShortcutPreference.cleanupObsoleteSettingsShortcutRegistration()
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        applyUITestingLaunchOverridesIfNeeded()
        AppSettingsPersistenceCoordinator.restorePersistedSettingsIfNeeded()
        AppSettingsPersistenceCoordinator.synchronizeCurrentSettings()
        AppLogger.app.info("Application did finish launching")

        hotKeyManager = GlobalHotKeyManager { [weak self] action in
            self?.performShortcutAction(action)
        }

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.line.3.summary", accessibilityDescription: "Quick Notes")
        }

        // Create the menu
        menu = NSMenu()

        // Add menu items
        let appendItem = NSMenuItem(title: "Daily Note", action: #selector(openAppendToDaily), keyEquivalent: "")
        let newNoteItem = NSMenuItem(title: "Create New Note", action: #selector(openNewNote), keyEquivalent: "")
        let editFileItem = NSMenuItem(title: "Edit Vault File", action: #selector(openEditVaultFile), keyEquivalent: "")
        menu?.addItem(appendItem)
        menu?.addItem(newNoteItem)
        menu?.addItem(editFileItem)
        menu?.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        menu?.addItem(settingsItem)
        menu?.addItem(NSMenuItem.separator())
        menu?.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appendMenuItem = appendItem
        newNoteMenuItem = newNoteItem
        editFileMenuItem = editFileItem
        settingsMenuItem = settingsItem
        applyShortcutPreferences()

        // Assign the menu to the status item
        statusItem?.menu = menu

        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            NSApp.setActivationPolicy(.regular)
        } else {
            // Keep the app running as an accessory (no dock icon)
            NSApp.setActivationPolicy(.accessory)
        }

        // Subscribe to space change notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutPreferencesDidChange),
            name: .shortcutPreferencesDidChange,
            object: nil
        )

        installLocalShortcutMonitor()
        openSetupOnFirstLaunchIfNeeded()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func applyUITestingLaunchOverridesIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }

        let environment = ProcessInfo.processInfo.environment
        if let vaultPath = environment["OSN_TEST_VAULT_PATH"], !vaultPath.isEmpty {
            let vaultURL = URL(fileURLWithPath: vaultPath)
            UserDefaults.standard.set(vaultURL.path, forKey: VaultStore.pathKey)
            UserDefaults.standard.set(vaultURL.lastPathComponent, forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        }

        if let editFilePath = environment["OSN_TEST_EDIT_FILE_PATH"], !editFilePath.isEmpty {
            UserDefaults.standard.set(editFilePath, forKey: NoteMode.editVaultFile.draftTitleKey)
            UserDefaults.standard.set(editFilePath, forKey: "draft.editVaultFile.search")
            UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTextKey)
        }
    }

    @objc func openAppendToDaily() {
        AppLogger.app.info("Opening daily note editor")
        let window = getOrBuildWindow(mode: .appendDaily)
        showWindow(window)
    }

    @objc func openNewNote() {
        AppLogger.app.info("Opening new note editor")
        let window = openNewNoteWindow(forceNew: hasVisibleWindow(mode: .newNote))
        showWindow(window)
    }

    private func openNewNoteWindow(forceNew: Bool) -> NSWindow {
        let shouldResumeDraft = !forceNew && NewNotePreferences.shouldResumeVisibleSession()

        if forceNew || !shouldResumeDraft {
            NewNotePreferences.clearDraft()
        }

        NewNotePreferences.startSession()
        return buildWindow(mode: .newNote)
    }

    @objc func openEditVaultFile() {
        AppLogger.app.info("Opening vault file editor")
        let window = buildWindow(mode: .editVaultFile)
        showWindow(window)
    }

    @objc func openSettings() {
        AppLogger.app.info("Opening settings")
        let window = getOrBuildWindow(mode: .settings)
        showWindow(window)
    }

    private func openSetupOnFirstLaunchIfNeeded() {
        guard !VaultStore.isVaultConfigured else { return }

        DispatchQueue.main.async { [weak self] in
            guard !VaultStore.isVaultConfigured else { return }
            AppLogger.app.info("Opening first-run setup")
            guard let window = self?.getOrBuildWindow(mode: .setup) else { return }
            self?.showWindow(window)
        }
    }

    func getOrBuildWindow(mode: NoteMode) -> NSWindow {
        if mode != .newNote,
           mode != .editVaultFile,
           let existingWindow = managedWindows.values.first(where: { $0.mode == mode && $0.window.isVisible })?.window {
            window = existingWindow
            return existingWindow
        }

        return buildWindow(mode: mode)
    }

    private func buildWindow(mode: NoteMode) -> NSWindow {

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Define window size
        let windowWidth: CGFloat = 350
        let windowHeight: CGFloat = 525
        let minimumWindowSize = NSSize(width: windowWidth * 0.5, height: windowHeight * 0.5)

        // Calculate position for top right (with some padding from edge)
        let padding: CGFloat = 10
        let cascadeOffset = CGFloat(managedWindows.count % 8) * 22
        let xPosition = screenFrame.maxX - windowWidth - padding - cascadeOffset
        let yPosition = screenFrame.maxY - windowHeight - padding - cascadeOffset

        // Create a custom floating window - this allows it to become key and accept input
        let window = FloatingWindow(
            contentRect: NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureLocalKeyEquivalents(for: window)
        window.delegate = self

        // Set window properties for floating behavior
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.minSize = minimumWindowSize
        window.isRestorable = false

        // Enable transparency and vibrancy
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let contentView = contentView(mode: mode, for: window)

        // Create a container view with rounded corners
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        // Add shadow to the hosting view
        hostingView.layer?.shadowColor = NSColor.black.cgColor
        hostingView.layer?.shadowOpacity = 0.3
        hostingView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        hostingView.layer?.shadowRadius = 10
        hostingView.layer?.masksToBounds = false

        window.contentView = hostingView

        managedWindows[ObjectIdentifier(window)] = (window, mode)
        self.window = window

        return window
    }

    @discardableResult
    func openWikiLink(_ link: String, from sourceWindow: NSWindow?, inNewWindow: Bool) -> NSWindow? {
        guard let note = VaultStore.note(forWikiLink: link) else {
            AppLogger.vault.warn("Could not resolve wiki link inside the selected vault")
            return nil
        }

        return openVaultNote(note, from: sourceWindow, inNewWindow: inNewWindow)
    }

    @discardableResult
    func openMarkdownLink(_ link: String, from sourceWindow: NSWindow?, inNewWindow: Bool) -> NSWindow? {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedLink),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            if !externalURLOpener(url) {
                AppLogger.app.warn("Could not open external Markdown link")
            }
            return nil
        }

        guard let note = VaultStore.note(forMarkdownLink: link) else {
            AppLogger.vault.warn("Could not resolve Markdown link inside the selected vault")
            return nil
        }

        return openVaultNote(note, from: sourceWindow, inNewWindow: inNewWindow)
    }

    private func openVaultNote(
        _ note: VaultNote,
        from sourceWindow: NSWindow?,
        inNewWindow: Bool
    ) -> NSWindow? {

        UserDefaults.standard.set(note.relativePath, forKey: NoteMode.editVaultFile.draftTitleKey)
        UserDefaults.standard.set(note.relativePath, forKey: "draft.editVaultFile.search")
        UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTextKey)

        if inNewWindow || sourceWindow == nil {
            let targetWindow = buildWindow(mode: .editVaultFile)
            showWindow(targetWindow)
            return targetWindow
        }

        guard let sourceWindow,
              let hostingView = sourceWindow.contentView as? NSHostingView<ContentView> else {
            return nil
        }

        hostingView.rootView = contentView(mode: .editVaultFile, for: sourceWindow)
        managedWindows[ObjectIdentifier(sourceWindow)] = (sourceWindow, .editVaultFile)
        showWindow(sourceWindow)
        return sourceWindow
    }

    private func contentView(mode: NoteMode, for window: NSWindow) -> ContentView {
        ContentView(
            mode: mode,
            closeWindow: { [weak self, weak window] in
                self?.closeWindow(window)
            },
            openWikiLink: { [weak self, weak window] link, inNewWindow in
                self?.openWikiLink(link, from: window, inNewWindow: inNewWindow)
            },
            openMarkdownLink: { [weak self, weak window] link, inNewWindow in
                self?.openMarkdownLink(link, from: window, inNewWindow: inNewWindow)
            },
            linkPreviewHover: { [weak self, weak window] event in
                self?.linkPreviewController.handle(event, from: window)
            }
        )
    }

    func showWindow(_ targetWindow: NSWindow? = nil) {
        guard let window = targetWindow ?? window else { return }
        self.window = window
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            NSApp.setActivationPolicy(.accessory)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        focusContentAfterWindowActivation(window)
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        if action == .appendDaily, shouldCloseVisibleWindow(for: action) {
            closeWindow(window)
            return
        }

        switch action {
        case .appendDaily:
            openAppendToDaily()
        case .newNote:
            let newWindow = openNewNoteWindow(forceNew: hasVisibleWindow(mode: .newNote))
            showWindow(newWindow)
        case .editVaultFile:
            openEditVaultFile()
        case .settings:
            break
        }
    }

    private func shouldCloseVisibleWindow(for action: ShortcutAction) -> Bool {
        guard let actionMode = action.noteMode else { return false }
        guard let window else { return false }
        return window.isVisible && mode(for: window) == actionMode
    }

    private func closeWindow(_ targetWindow: NSWindow? = nil) {
        guard let targetWindow = targetWindow ?? NSApp.keyWindow ?? window else { return }
        targetWindow.close()
        restoreAccessoryActivationPolicyIfNeeded()
    }

    private func restoreAccessoryActivationPolicyIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        DispatchQueue.main.async {
            guard !self.managedWindows.values.contains(where: { $0.window.isVisible }) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func focusContentAfterWindowActivation(_ window: NSWindow) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode(for: window)?.startsWithEditorFocus == true else { return }
            NotificationCenter.default.post(name: .editorShouldFocus, object: window)
        }
    }

    func mode(for window: NSWindow) -> NoteMode? {
        managedWindows[ObjectIdentifier(window)]?.mode
    }

    private func hasVisibleWindow(mode: NoteMode) -> Bool {
        managedWindows.values.contains { $0.mode == mode && $0.window.isVisible }
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        for managedWindow in managedWindows.values where managedWindow.window.isVisible {
            managedWindow.window.orderFrontRegardless()
        }
    }

    @objc func shortcutPreferencesDidChange(_ notification: Notification) {
        applyShortcutPreferences()
    }

    private func applyShortcutPreferences() {
        ShortcutPreference.cleanupObsoleteSettingsShortcutRegistration()
        appendMenuItem?.removeShortcut()
        newNoteMenuItem?.removeShortcut()
        editFileMenuItem?.removeShortcut()
        settingsMenuItem?.removeShortcut()
        appendMenuItem?.applyShortcut(.appendDaily)
        newNoteMenuItem?.applyShortcut(.newNote)
        editFileMenuItem?.applyShortcut(.editVaultFile)
        hotKeyManager?.registerAll()
    }

    private func installLocalShortcutMonitor() {
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard NSApp.isActive else { return event }
            guard KeyboardEventRouting.shouldHandleLocalShortcut(event) else { return event }

            if self?.window?.isKeyWindow == true,
               self?.matches(event, action: .settings) == true {
                self?.openSettings()
                return nil
            }

            if event.charactersIgnoringModifiers?.lowercased() == "q",
               ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command {
                NSApp.terminate(nil)
                return nil
            }

            if event.charactersIgnoringModifiers?.lowercased() == "w",
               ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command {
                self?.closeWindow(self?.window)
                return nil
            }

            return event
        }
    }

    private func matches(_ event: NSEvent, action: ShortcutAction) -> Bool {
        let shortcut = action.shortcut
        return ShortcutPreference.normalized(event.charactersIgnoringModifiers ?? "") == shortcut.key
            && ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == shortcut.modifiers
    }

    private func configureLocalKeyEquivalents(for window: NSWindow) {
        guard let floatingWindow = window as? FloatingWindow else { return }
        floatingWindow.escapeHandler = { [weak self, weak window] in
            self?.closeWindow(window)
        }
        floatingWindow.keyEquivalentHandler = { [weak self, weak window] event in
            guard let self else { return false }
            guard KeyboardEventRouting.shouldHandleLocalShortcut(event) else { return false }

            if self.matches(event, action: .settings) {
                self.openSettings()
                return true
            }

            for action in ShortcutAction.globalActions where self.matches(event, action: action) {
                self.performShortcutAction(action)
                return true
            }

            guard ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command else {
                return false
            }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                self.closeWindow(window)
                return true
            case "q":
                NSApp.terminate(nil)
                return true
            default:
                return false
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        linkPreviewController.sourceWindowClosed(closedWindow)
        managedWindows.removeValue(forKey: ObjectIdentifier(closedWindow))
        if window === closedWindow {
            window = managedWindows.values.first(where: { $0.window.isVisible })?.window
        }
        restoreAccessoryActivationPolicyIfNeeded()
    }
}
