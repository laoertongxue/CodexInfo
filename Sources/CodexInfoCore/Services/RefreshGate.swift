import Foundation

/// Serializes refresh work and coalesces requests that arrive during a run.
///
/// One run is active at a time. Any number of requests that arrive while it
/// is running schedule exactly one rerun, so a manual scan cannot be lost and
/// the app never starts two snapshot builds at once.
public actor RefreshGate {
    private var running = false
    private var queued = false

    public init() {}

    /// Runs the operation, or queues one rerun when work is already running.
    ///
    /// - Parameter operation: the work that builds and publishes a snapshot.
    public func run(_ operation: @Sendable @escaping () async -> Void) async {
        if running {
            queued = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            queued = false
            await operation()
        } while queued
    }
}
