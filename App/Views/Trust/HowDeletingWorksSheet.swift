import SwiftUI

struct HowDeletingWorksSheet: View {
    @EnvironmentObject private var trustState: TrustState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How deleting works")
                    .appText(.title)
                    .accessibilityIdentifier("how.deleting.works.title")
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Approve adds to your tray")
                            .appText(.body)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("You delete from the tray")
                            .appText(.body)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Apple asks you to confirm")
                            .appText(.body)
                    }
                }
                
                Text("Deleted photos stay in Recently Deleted for 30 days.")
                    .appText(.body)
                    .accessibilityIdentifier("how.deleting.works.recently.deleted")
                
                NavigationLink("How to get photos back", destination: HowToRecoverSheet())
                    .appText(.body)
                    .foregroundStyle(Color.actionPrimary)
                    .accessibilityIdentifier("how.deleting.works.recover.link")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Got it") {
                    trustState.setHasReadHowDeletingWorks(true)
                    dismiss()
                }
                .accessibilityIdentifier("how.deleting.works.got.it")
            }
        }
    }
}

#Preview {
    HowDeletingWorksSheet()
}