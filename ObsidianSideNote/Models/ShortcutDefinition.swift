import AppKit

struct ShortcutDefinition: Equatable {
    var key: String
    var modifiers: NSEvent.ModifierFlags

    var addingShift: ShortcutDefinition {
        ShortcutDefinition(key: key, modifiers: modifiers.union(.shift))
    }

    var displayValue: String {
        "\(ShortcutPreference.displayModifiers(modifiers)) \(displayKey)"
            .trimmingCharacters(in: .whitespaces)
    }

    private var displayKey: String {
        key == "space" ? "Space" : key.uppercased()
    }
}
