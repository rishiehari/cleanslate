import SwiftUI

/// Spacing scale. Views use these, never loose numbers.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    /// Room at the bottom of scrolling content so the floating approval bar never hides the last photo.
    static let barClearance: CGFloat = 96
}

enum Radius {
    static let s: CGFloat = 8
    static let photo: CGFloat = 12
    static let m: CGFloat = 14
    static let l: CGFloat = 22
    static let pill: CGFloat = 999
}

enum IconSize {
    static let badge: CGFloat = 22
    static let row: CGFloat = 28
    static let hero: CGFloat = 64
}

/// Role-named colors (asset catalog, light + dark). Never name by appearance.
extension Color {
    static let actionPrimary = Color("actionPrimary")
    static let keepAccent = Color("keepAccent")
    static let deleteAccent = Color("deleteAccent")
    static let protectedAccent = Color("protectedAccent")
    static let warningAccent = Color("warningAccent")
    /// Text/icons drawn ON an accent fill (white in light mode, near-black in dark mode).
    static let onAccent = Color("onAccent")
    static let surfaceBackground = Color("surfaceBackground")
    static let surfaceCard = Color("surfaceCard")
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
}

/// Provisional window-layout values; validate at AX5 and on physical iPad before release.
enum AdaptiveLayout {
    static let protectionInspectorWidth: CGFloat = 320
    static let minimumProtectionListWidth: CGFloat = 360

    static func showsProtectionInspector(width: CGFloat, accessibilityText: Bool) -> Bool {
        !accessibilityText && width >= protectionInspectorWidth + minimumProtectionListWidth + Spacing.l
    }

    static let minimumComparisonPhotoWidth: CGFloat = 300
    static let readableContentWidth: CGFloat = 760
    static let minimumTileWidth: CGFloat = 100
    static let accessibleTileWidth: CGFloat = 200
    static let reviewQueueWidth: CGFloat = 300
    static let minimumReviewDetailWidth: CGFloat = 640

    static func showsReviewQueue(width: CGFloat, accessibilityText: Bool) -> Bool {
        !accessibilityText && width >= reviewQueueWidth + minimumReviewDetailWidth
    }

    static func usesHorizontalComparison(width: CGFloat, accessibilityText: Bool) -> Bool {
        !accessibilityText && width >= minimumComparisonPhotoWidth * 2 + Spacing.xs
    }
}
