import Foundation
import SwiftUI

/// Shared keyboard shortcuts for the CleanSlate app
enum KeyboardShortcut {
    /// Approve current selection
    static let approve = KeyEquivalent("k")
    
    /// Skip current item
    static let skip = KeyEquivalent("l")
    
    /// Cancel current operation
    static let cancel = KeyEquivalent(.escape)
    
    /// Keep left photo (for review)
    static let keepLeft = KeyEquivalent("h")
    
    /// Delete photo (for review)
    static let delete = KeyEquivalent("d")
    
    /// Toggle search
    static let search = KeyEquivalent("f")
    
    /// Undo last action
    static let undo = KeyEquivalent("z")
    
    /// Select all items
    static let selectAll = KeyEquivalent("a")
}

/// Shared keyboard command handling for review views
class ReviewKeyboardHandler: ObservableObject {
    @Published var isFocused = false
    
    func handleApprove() {
        // Implementation to be handled by specific views
    }
    
    func handleSkip() {
        // Implementation to be handled by specific views
    }
    
    func handleCancel() {
        // Implementation to be handled by specific views
    }
}