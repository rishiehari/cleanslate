import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text("Your privacy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                
                // Main description
                Text("CleanSlate checks your photos right here. No account, no ads, no tracking, and CleanSlate has no servers to send anything to.")
                    .font(.body)
                    .padding(.bottom)
                
                // What CleanSlate does
                VStack(alignment: .leading, spacing: 12) {
                    Text("CleanSlate does")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    List {
                        Text("• Checks photos on this iPhone")
                        Text("• Saves a small index to make the next check faster")
                        Text("• Keeps a private activity record you can delete")
                    }
                    .listStyle(PlainListStyle())
                }
                
                // What CleanSlate never does
                VStack(alignment: .leading, spacing: 12) {
                    Text("CleanSlate never does")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    List {
                        Text("• Upload photos")
                        Text("• Collect analytics")
                        Text("• Show ads")
                        Text("• Need an account")
                        Text("• Delete without your OK")
                    }
                    .listStyle(PlainListStyle())
                }
                
                // Verification section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Check it yourself")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    List {
                        Text("• Turn on Airplane Mode: CleanSlate works the same.")
                        Text("• The App Store listing says *Data Not Collected*.")
                        Text("• In Settings → Privacy & Security → App Privacy Report, you can see which apps used the network.")
                    }
                    .listStyle(PlainListStyle())
                }
                
                // iCloud note
                VStack(alignment: .leading, spacing: 12) {
                    Text("iCloud originals")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("If you turn on *iCloud originals*, Photos downloads your own originals from iCloud so they can be checked. CleanSlate itself still sends nothing.")
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PrivacyView()
}