import AppKit

extension ImportCandidateSelectionIntent {
    static func currentKeyboardIntent() -> Self {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            return .range
        }
        if modifiers.contains(.command) {
            return .toggle
        }
        return .replace
    }
}
