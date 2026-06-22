import AppKit

struct ShortcutDefinition: Equatable {
    var key: String
    var modifiers: NSEvent.ModifierFlags

    var displayValue: String {
        "\(ShortcutPreference.displayModifiers(modifiers)) \(displayKey)"
            .trimmingCharacters(in: .whitespaces)
    }

    private var displayKey: String {
        key == "space" ? "Space" : key.uppercased()
    }
}
