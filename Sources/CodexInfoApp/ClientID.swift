import Foundation

/// The clients that have their own quota panel.
enum ClientID: String, CaseIterable, Hashable, Sendable {
    case qoder
    case deepSeekHarness
    case miniMaxCode
}
