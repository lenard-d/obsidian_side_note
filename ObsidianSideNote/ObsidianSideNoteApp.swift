//
//  ObsidianSideNoteApp.swift
//  ObsidianSideNote
//
//  Created by Luke Smith on 11/27/25.
//

import SwiftUI
import AppKit

@main
struct ObsidianSideNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var menu: NSMenu?
    private var appendMenuItem: NSMenuItem?
    private var newNoteMenuItem: NSMenuItem?
    private var editFileMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var hotKeyManager: GlobalHotKeyManager?
    private var currentMode: NoteMode?
    private var localShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let appendItem = NSMenuItem(title: "Append to Daily Note", action: #selector(openAppendToDaily), keyEquivalent: "")
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

        // Keep the app running as an accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)

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
    }

    @objc func openAppendToDaily() {
        // Open window in "append to daily" mode
        _ = getOrBuildWindow(mode: .appendDaily)
        showWindow()
    }

    @objc func openNewNote() {
        openNewNoteWindow(forceNew: false)
        showWindow()
    }

    private func openNewNoteWindow(forceNew: Bool) {
        if forceNew {
            NewNotePreferences.clearDraft()
        }

        if !forceNew,
           currentMode == .newNote,
           window?.isVisible == true,
           NewNotePreferences.shouldResumeVisibleSession() {
            showWindow()
            return
        }

        if !forceNew, currentMode == .newNote, window?.isVisible == true {
            NewNotePreferences.clearDraft()
        }

        NewNotePreferences.startSession()
        _ = getOrBuildWindow(mode: .newNote)
    }

    @objc func openEditVaultFile() {
        _ = getOrBuildWindow(mode: .editVaultFile)
        showWindow()
    }

    @objc func openSettings() {
        // Open window in "settings" mode
        _ = getOrBuildWindow(mode: .settings)
        showWindow()
    }

    func getOrBuildWindow(mode: NoteMode) -> NSWindow {
        currentMode = mode

        // If window exists, just update the content view with new mode
        if let existingWindow = window {
            existingWindow.contentView = NSHostingView(rootView: ContentView(mode: mode, closeWindow: { [weak self] in
                self?.window?.orderOut(nil)
            }))
            return existingWindow
        }

        // Get the screen dimensions
        guard let screen = NSScreen.main else {
            fatalError("No main screen found")
        }
        let screenFrame = screen.visibleFrame

        // Define window size
        let windowWidth: CGFloat = 350
        let windowHeight: CGFloat = 525

        // Calculate position for top right (with some padding from edge)
        let padding: CGFloat = 10
        let xPosition = screenFrame.maxX - windowWidth - padding
        let yPosition = screenFrame.maxY - windowHeight - padding

        // Create the SwiftUI view with the specified mode
        let contentView = ContentView(mode: mode, closeWindow: { [weak self] in
            self?.window?.orderOut(nil)
        })

        // Create a custom floating window - this allows it to become key and accept input
        let window = FloatingWindow(
            contentRect: NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Set window properties for floating behavior
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Enable transparency and vibrancy
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

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

        // Store reference
        self.window = window

        return window
    }

    func showWindow() {
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .appendDaily:
            openAppendToDaily()
        case .newNote:
            openNewNoteWindow(forceNew: true)
            showWindow()
        case .editVaultFile:
            openEditVaultFile()
        case .settings:
            break
        }
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        // Ensure window stays visible when switching spaces (only if it's currently shown)
        if let window = window, window.isVisible {
            window.orderFrontRegardless()
        }
    }

    @objc func shortcutPreferencesDidChange(_ notification: Notification) {
        applyShortcutPreferences()
    }

    private func applyShortcutPreferences() {
        appendMenuItem?.applyShortcut(.appendDaily)
        newNoteMenuItem?.applyShortcut(.newNote)
        editFileMenuItem?.applyShortcut(.editVaultFile)
        settingsMenuItem?.keyEquivalent = ""
        settingsMenuItem?.keyEquivalentModifierMask = []
        hotKeyManager?.registerAll()
    }

    private func installLocalShortcutMonitor() {
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard NSApp.isActive else { return event }

            if self?.matches(event, action: .settings) == true {
                self?.openSettings()
                return nil
            }

            if event.charactersIgnoringModifiers?.lowercased() == "q",
               ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command {
                NSApp.terminate(nil)
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
}
