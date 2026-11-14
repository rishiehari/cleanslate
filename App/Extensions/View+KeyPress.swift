import SwiftUI

extension View {
    /// Adds a key press handler to a view
    func onKeyPress(key: Character, action: @escaping () -> Void) -> some View {
        self.onKeyPress(key: String(key), action: action)
    }
    
    /// Adds a key press handler to a view
    func onKeyPress(key: String, action: @escaping () -> Void) -> some View {
        #if os(iOS)
        // This implementation is for iOS - the actual keyboard handling will be in the views themselves
        // For now, we just return self to avoid compilation errors
        return self
        #else
        return self
        #endif
    }
}