import SwiftUI

struct HowToRecoverSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to get photos back")
                    .appText(.title)
                    .accessibilityIdentifier("how.to.recover.title")
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Open the Photos app")
                            .appText(.body)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Go to Recently Deleted")
                            .appText(.body)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Select the photos you want to recover")
                            .appText(.body)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("4.")
                            .appText(.body)
                            .fontWeight(.bold)
                            .frame(width: 24, alignment: .leading)
                        
                        Text("Tap Recover")
                            .appText(.body)
                    }
                }
                
                Text("After 30 days, or after you empty Recently Deleted, photos can't be recovered.")
                    .appText(.body)
                    .accessibilityIdentifier("how.to.recover.cannot.recover")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                }
                .accessibilityIdentifier("how.to.recover.close")
            }
        }
    }
}

#Preview {
    HowToRecoverSheet()
}