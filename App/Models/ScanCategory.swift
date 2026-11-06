import Foundation

/// What the user can review. Only categories with a working engine are `isAvailable`.
enum ScanCategory: String, CaseIterable, Identifiable {
    case exact, similar, videos, screenshots, largeFiles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: "Exact copies"
        case .similar: "Similar & bursts"
        case .videos: "Videos"
        case .screenshots: "Screenshots"
        case .largeFiles: "Large files"
        }
    }

    var symbol: String {
        switch self {
        case .exact: "square.on.square"
        case .similar: "square.stack.3d.down.right"
        case .videos: "video"
        case .screenshots: "camera.viewfinder"
        case .largeFiles: "externaldrive"
        }
    }

    var summary: String {
        switch self {
        case .exact: "Byte-identical copies. Quickest to clear."
        case .similar: "Near-identical shots. You choose what to remove."
        case .videos: "Identical copies of the same video."
        case .screenshots: "Old screenshots and screen recordings. You pick."
        case .largeFiles: "The biggest videos on your iPhone. You pick."
        }
    }

    var isAvailable: Bool { true }

    /// Screenshots and large files have no "keep one" photo; the user picks items to delete.
    var standaloneKind: StandaloneKind? {
        switch self {
        case .screenshots: .screenshotsAndRecordings
        case .largeFiles: .largeFiles
        default: nil
        }
    }

    var itemNoun: (singular: String, plural: String) {
        standaloneKind == nil ? ("group", "groups") : ("item", "items")
    }

    var groupKind: GroupKind? {
        switch self {
        case .exact, .videos: .exact
        case .similar: .similar
        default: nil
        }
    }
}
