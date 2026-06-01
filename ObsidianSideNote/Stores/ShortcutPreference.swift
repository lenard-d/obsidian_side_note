import AppKit

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
        let storedKey = UserDefaults.standard.string(forKey: action.preferenceKey) ?? action.defaultKey
        let rawModifiers = UserDefaults.standard.integer(forKey: action.modifierPreferenceKey)
        let modifiers = rawModifiers == 0 ? NSEvent.ModifierFlags.command : modifierFlags(from: rawModifiers)
        return ShortcutDefinition(
            key: normalized(storedKey, fallback: action.defaultKey),
            modifiers: menuModifierFlags(from: modifiers)
        )
    }

    static func displayValue(for action: ShortcutAction) -> String {
        definition(for: action).displayValue
    }

    static func set(_ value: String, modifiers: NSEvent.ModifierFlags, for action: ShortcutAction) {
        let normalizedValue = normalized(value, fallback: action.defaultKey)
        let normalizedModifiers = menuModifierFlags(from: modifiers)
        UserDefaults.standard.set(normalizedValue, forKey: action.preferenceKey)
        UserDefaults.standard.set(rawValue(for: normalizedModifiers), forKey: action.modifierPreferenceKey)
        NotificationCenter.default.post(name: .shortcutPreferencesDidChange, object: nil)
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
        return result.isEmpty ? .command : result
    }

    private static func rawValue(for modifiers: NSEvent.ModifierFlags) -> Int {
        var rawValue = 0
        if modifiers.contains(.command) { rawValue |= 1 << 0 }
        if modifiers.contains(.option) { rawValue |= 1 << 1 }
        if modifiers.contains(.control) { rawValue |= 1 << 2 }
        if modifiers.contains(.shift) { rawValue |= 1 << 3 }
        return rawValue
    }

    private static func modifierFlags(from rawValue: Int) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if rawValue & (1 << 0) != 0 { modifiers.insert(.command) }
        if rawValue & (1 << 1) != 0 { modifiers.insert(.option) }
        if rawValue & (1 << 2) != 0 { modifiers.insert(.control) }
        if rawValue & (1 << 3) != 0 { modifiers.insert(.shift) }
        return modifiers
    }
}
