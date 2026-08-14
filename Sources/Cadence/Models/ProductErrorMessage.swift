import Foundation

/// Keeps recovery copy in a predictable order: technical event, preserved
/// state, then the next action available to the user.
struct ProductErrorMessage: Equatable, Sendable {
    let detail: String
    let preservedState: String
    let recoveryAction: String

    var text: String {
        "\(detail)\n\n\(preservedState) \(recoveryAction)"
    }
}
