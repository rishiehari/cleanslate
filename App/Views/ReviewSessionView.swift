import SwiftUI

/// Walks through a queue of groups: Approve or Skip opens the next one, so a long inbox
/// is one smooth pass instead of "back, tap the next row" 200 times.
struct ReviewSessionView: View {
    let groups: [PhotoReviewGroup]
    let tray: DeletionTray
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let group = groups[index]
        ReviewGroupView(group: group, tray: tray,
                        position: groups.count > 1 ? "\(index + 1) of \(groups.count)" : nil) {
            if index + 1 < groups.count { index += 1 } else { dismiss() }
        }
        .id(group.id)
    }
}
