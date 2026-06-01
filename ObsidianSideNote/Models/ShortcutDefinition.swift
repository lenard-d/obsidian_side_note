import AppKit

struct ShortcutDefinition: Equatable {
    var key: String
    var modifiers: NSEvent.ModifierFlags

    var displayValue: String {
        "\(ShortcutPreference.displayModifiers(modifiers)) \(key.uppercased())"
            .trimmingCharacters(in: .whitespaces)
    }
}
