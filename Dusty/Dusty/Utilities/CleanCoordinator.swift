import Foundation

/// A process-wide gate so only one clean runs at a time, regardless of which entry
/// point starts it: the panel's confirm, a Shortcuts action, or the scheduled
/// auto-clean. Each of those builds its own `CleanerEngine`, so the view model's
/// `isCleaning` flag cannot coordinate across them; this shared gate can.
///
/// Every entry point hops to the main actor before cleaning, so `beginClean`'s
/// check-and-set runs without an intervening suspension and is effectively atomic.
@MainActor
final class CleanCoordinator {
    static let shared = CleanCoordinator()
    private init() {}

    private(set) var isCleaning = false

    /// Acquire the gate. Returns `false` if a clean is already in flight; the caller
    /// must not start one. Balance a successful acquisition with `endClean()`.
    func beginClean() -> Bool {
        if isCleaning { return false }
        isCleaning = true
        return true
    }

    func endClean() {
        isCleaning = false
    }
}
