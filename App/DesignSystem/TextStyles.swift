import SwiftUI

/// One text style = font + weight + design (+ case/tracking when needed), applied with ONE modifier.
/// System fonts only, all relative to Dynamic Type text styles.
struct AppTextStyle: Sendable {
    var font: Font
    var textCase: Text.Case?
    var tracking: CGFloat = 0
}

extension AppTextStyle {
    static let heroNumber = AppTextStyle(font: .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
    static let title = AppTextStyle(font: .system(.title2, weight: .bold))
    static let groupTitle = AppTextStyle(font: .system(.headline))
    static let body = AppTextStyle(font: .system(.body))
    static let secondary = AppTextStyle(font: .system(.subheadline))
    static let caption = AppTextStyle(font: .system(.caption))
    static let chip = AppTextStyle(font: .system(.caption, weight: .semibold))
    static let badge = AppTextStyle(font: .system(.caption2, weight: .bold))
}

extension View {
    func appText(_ style: AppTextStyle) -> some View {
        font(style.font).textCase(style.textCase).tracking(style.tracking)
    }
}
