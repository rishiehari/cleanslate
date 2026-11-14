import SwiftUI

struct HowDeletingWorksSheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How deleting works")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                
                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    HowDeletingStep(number: 1, text: "Approve adds to your tray")
                    HowDeletingStep(number: 2, text: "You delete from the tray")
                    HowDeletingStep(number: 3, text: "Apple asks you to confirm")
                }
                
                // Additional information
                VStack(alignment: .leading, spacing: 12) {
                    Text("Deleted photos stay in Recently Deleted for 30 days.")
                        .font(.body)
                    
                    Text("How to get photos back")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Photos can be recovered from Recently Deleted in the Photos app for 30 days after deletion.")
                }
                
                // Button
                Button("Got it") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HowDeletingStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue)
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
                .overlay(
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    HowDeletingWorksSheet()
}