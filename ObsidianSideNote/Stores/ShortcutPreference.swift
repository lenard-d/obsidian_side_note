import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

struct ShortcutPreference {
    static func normalized(_ value: String, fallback: String = "d") -> String {
        let trimmedValue = value
            .replacingOccurrences(of: "⌘", with: "")
            .replacingOccurrences(of: "⌃", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmedValue.first.map(String.init) ?? fallback
    }

    static func definition(for action: ShortcutAction) -> ShortcutDefinition {
        if !action.isGlobal {
            return localDefinition(for: action)
        }

        guard let shortcutName = action.globalShortcutName else {
            return ShortcutDefinition(key: action.defaultKey, modifiers: action.defaultModifiers)
        }

        migrateLegacyShortcutIfNeeded(for: action, shortcutName: shortcutName)

        guard let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) else {
            return ShortcutDefinition(key: action.defaultKey, modifiers: action.defaultModifiers)
        }

        return ShortcutDefinition(
            key: GlobalHotKeyManager.key(forKeyCode: shortcut.carbonKeyCode) ?? action.defaultKey,
            modifiers: menuModifierFlags(from: shortcut.modifiers)
        )
    }

    static func displayValue(for action: ShortcutAction) -> String {
        definition(for: action).displayValue
    }

    static func set(_ value: String, modifiers: NSEvent.ModifierFlags, for action: ShortcutAction) {
        let normalizedValue = normalized(value, fallback: action.defaultKey)
        let normalizedModifiers = menuModifierFlags(from: modifiers)
        if let shortcutName = action.globalShortcutName {
            KeyboardShortcuts.setShortcut(
                keyboardShortcut(key: normalizedValue, modifiers: normalizedModifiers),
                for: shortcutName
            )
        } else {
            storeLocalDefinition(key: normalizedValue, modifiers: normalizedModifiers, for: action)
            KeyboardShortcuts.setShortcut(
                keyboardShortcut(key: normalizedValue, modifiers: normalizedModifiers),
                for: action.recorderShortcutName
            )
        }
        AppConfigStore.saveShortcut(action: action, key: normalizedValue, modifiers: normalizedModifiers)
        NotificationCenter.default.post(name: .shortcutPreferencesDidChange, object: nil)
    }

    static func resetToDefault(for action: ShortcutAction) {
        set(action.defaultKey, modifiers: action.defaultModifiers, for: action)
        syncRecorderShortcut(for: action)
    }

    static func restore(_ shortcut: ShortcutDefinition, for action: ShortcutAction) {
        let normalizedValue = normalized(shortcut.key, fallback: action.defaultKey)
        let normalizedModifiers = menuModifierFlags(from: shortcut.modifiers)

        if let shortcutName = action.globalShortcutName {
            guard let keyboardShortcut = keyboardShortcut(key: normalizedValue, modifiers: normalizedModifiers) else {
                return
            }
            KeyboardShortcuts.setShortcut(keyboardShortcut, for: shortcutName)
            return
        }

        storeLocalDefinition(key: normalizedValue, modifiers: normalizedModifiers, for: action)
        syncRecorderShortcut(for: action)
    }

    static func syncRecorderShortcut(for action: ShortcutAction) {
        let definition = definition(for: action)
        KeyboardShortcuts.setShortcut(
            keyboardShortcut(key: definition.key, modifiers: definition.modifiers),
            for: action.recorderShortcutName
        )
    }

    static func keyboardShortcut(key: String, modifiers: NSEvent.ModifierFlags) -> KeyboardShortcuts.Shortcut? {
        guard let keyCode = GlobalHotKeyManager.keyCode(for: key) else { return nil }
        return KeyboardShortcuts.Shortcut(
            carbonKeyCode: keyCode,
            carbonModifiers: carbonModifiers(from: menuModifierFlags(from: modifiers))
        )
    }

    static func displayModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    static func menuModifierFlags(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    static func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> Int {
        var rawValue = 0
        if modifiers.contains(.command) { rawValue |= cmdKey }
        if modifiers.contains(.option) { rawValue |= optionKey }
        if modifiers.contains(.control) { rawValue |= controlKey }
        if modifiers.contains(.shift) { rawValue |= shiftKey }
        return rawValue
    }

    private static func localDefinition(for action: ShortcutAction) -> ShortcutDefinition {
        let key = UserDefaults.standard.string(forKey: action.preferenceKey) ?? action.defaultKey
        let rawModifiers = UserDefaults.standard.object(forKey: action.modifierPreferenceKey) as? Int
        let modifiers = rawModifiers.map(legacyModifierFlags(from:)) ?? action.defaultModifiers
        return ShortcutDefinition(
            key: normalized(key, fallback: action.defaultKey),
            modifiers: menuModifierFlags(from: modifiers)
        )
    }

    private static func storeLocalDefinition(key: String, modifiers: NSEvent.ModifierFlags, for action: ShortcutAction) {
        UserDefaults.standard.set(normalized(key, fallback: action.defaultKey), forKey: action.preferenceKey)
        UserDefaults.standard.set(legacyRawValue(from: modifiers), forKey: action.modifierPreferenceKey)
    }

    private static func migrateLegacyShortcutIfNeeded(for action: ShortcutAction, shortcutName: KeyboardShortcuts.Name) {
        guard KeyboardShortcuts.getShortcut(for: shortcutName) == nil,
              UserDefaults.standard.object(forKey: action.preferenceKey) != nil else {
            return
        }

        let storedKey = UserDefaults.standard.string(forKey: action.preferenceKey) ?? action.defaultKey
        let rawModifiers = UserDefaults.standard.integer(forKey: action.modifierPreferenceKey)
        let modifiers = rawModifiers == 0 ? action.defaultModifiers : legacyModifierFlags(from: rawModifiers)

        KeyboardShortcuts.setShortcut(
            keyboardShortcut(key: storedKey, modifiers: modifiers),
            for: shortcutName
        )
        UserDefaults.standard.removeObject(forKey: action.preferenceKey)
        UserDefaults.standard.removeObject(forKey: action.modifierPreferenceKey)
    }

    private static func legacyRawValue(from modifiers: NSEvent.ModifierFlags) -> Int {
        let normalizedModifiers = menuModifierFlags(from: modifiers)
        var rawValue = 0
        if normalizedModifiers.contains(.command) { rawValue |= 1 << 0 }
        if normalizedModifiers.contains(.option) { rawValue |= 1 << 1 }
        if normalizedModifiers.contains(.control) { rawValue |= 1 << 2 }
        if normalizedModifiers.contains(.shift) { rawValue |= 1 << 3 }
        return rawValue
    }

    private static func legacyModifierFlags(from rawValue: Int) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if rawValue & (1 << 0) != 0 { modifiers.insert(.command) }
        if rawValue & (1 << 1) != 0 { modifiers.insert(.option) }
        if rawValue & (1 << 2) != 0 { modifiers.insert(.control) }
        if rawValue & (1 << 3) != 0 { modifiers.insert(.shift) }
        return modifiers
    }
}
