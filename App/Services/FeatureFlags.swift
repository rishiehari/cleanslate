import Foundation

/// Build-time switches. They only ever hide NEW user-facing surfaces. Safety enforcement is never behind a flag.
enum FeatureFlags {
    /// N05: entry points that create protection rules. Enforcement of existing rules does not depend on this.
    /// On in debug builds unless `-disableProtectionRulesUI` is passed; off in release until the owner enables it.
    static var protectionRulesUI: Bool { protectionRulesUI(arguments: ProcessInfo.processInfo.arguments) }

    static func protectionRulesUI(arguments: [String]) -> Bool {
        #if DEBUG
        return !arguments.contains("-disableProtectionRulesUI")
        #else
        return false
        #endif
    }
}
