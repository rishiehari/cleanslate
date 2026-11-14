import SwiftUI

struct HowToRecoverSheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to get photos back")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                
                // Recovery steps
                VStack(alignment: .leading, spacing: 16) {
                    RecoveryStep(number: 1, text: "In the Photos app, open Recently Deleted")
                    RecoveryStep(number: 2, text: "Select the photos you want to recover")
                    RecoveryStep(number: 3, text: "Tap Recover")
                }
                
                // Additional information
                VStack(alignment: .leading, spacing: 12) {
                    Text("After 30 days, or after you empty Recently Deleted, photos can't be recovered.")
                        .font(.body)
                        .foregroundColor(.secondary)
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

struct RecoveryStep: View {
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
    HowToRecoverSheet()
}