import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your privacy")
                    .appText(.title)
                    .accessibilityIdentifier("privacy.title")
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("CleanSlate does")
                        .appText(.groupTitle)
                    
                    List {
                        Text("Checks photos on this iPhone")
                            .appText(.body)
                        
                        Text("Saves a small index to make the next check faster")
                            .appText(.body)
                        
                        Text("Keeps a private activity record you can delete")
                            .appText(.body)
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.do")
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("CleanSlate never does")
                        .appText(.groupTitle)
                    
                    List {
                        Text("Upload photos")
                            .appText(.body)
                        
                        Text("Collect analytics")
                            .appText(.body)
                        
                        Text("Show ads")
                            .appText(.body)
                        
                        Text("Need an account")
                            .appText(.body)
                        
                        Text("Delete without your OK")
                            .appText(.body)
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.never.do")
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Check it yourself")
                        .appText(.groupTitle)
                    
                    List {
                        Text("Turn on Airplane Mode: CleanSlate works the same.")
                            .appText(.body)
                        
                        Text("The App Store listing says *Data Not Collected*.")
                            .appText(.body)
                        
                        Text("In Settings → Privacy & Security → App Privacy Report, you can see which apps used the network.")
                            .appText(.body)
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.check.it.yourself")
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("iCloud originals note")
                        .appText(.groupTitle)
                    
                    Text("If you turn on *iCloud originals*, Photos downloads your own originals from iCloud so they can be checked. CleanSlate itself still sends nothing.")
                        .appText(.body)
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PrivacyView()
}