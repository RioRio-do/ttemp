import AppKit

/// A manual interaction receipt, not a pixel/visibility assertion.
struct StatusItemInteractionCheck {
    private var left = false
    private var right = false

    /// Reports only the first completion, and ignores non-mouse/programmatic actions.
    mutating func record(_ type: NSEvent.EventType?) -> Bool {
        guard !(left && right) else { return false }
        if type == .leftMouseUp { left = true }
        if type == .rightMouseUp { right = true }
        return left && right
    }
}
