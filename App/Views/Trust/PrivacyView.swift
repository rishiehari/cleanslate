import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Your privacy").appText(.title)
                    .accessibilityIdentifier("privacy.title")
                
                Text("CleanSlate keeps your photos private and secure. Here's what it does — and doesn't — do on this iPhone:")
                    .appText(.body)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, Spacing.s)
                
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("CleanSlate does").appText(.groupTitle)
                        .accessibilityIdentifier("privacy.do.title")
                    
                    List {
                        PrivacyItem(
                            title: "Check photos on this iPhone",
                            description: "CleanSlate analyzes your photos right here on this device."
                        )
                        
                        PrivacyItem(
                            title: "Save a small index to make the next check faster",
                            description: "It stores minimal data locally to speed up future scans."
                        )
                        
                        PrivacyItem(
                            title: "Keep a private activity record you can delete",
                            description: "CleanSlate logs what it finds for your reference, but keeps it private and you can delete it at any time."
                        )
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.do.list")
                }
                
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("CleanSlate never does").appText(.groupTitle)
                        .accessibilityIdentifier("privacy.dont.title")
                    
                    List {
                        PrivacyItem(
                            title: "Upload photos",
                            description: "No photos leave your iPhone. CleanSlate analyzes them locally only."
                        )
                        
                        PrivacyItem(
                            title: "Collect analytics",
                            description: "CleanSlate doesn't collect or transmit any usage data."
                        )
                        
                        PrivacyItem(
                            title: "Show ads",
                            description: "There are no advertisements in CleanSlate."
                        )
                        
                        PrivacyItem(
                            title: "Need an account",
                            description: "CleanSlate works completely offline without requiring registration."
                        )
                        
                        PrivacyItem(
                            title: "Delete without your OK",
                            description: "Nothing is deleted without your explicit approval and Apple's confirmation prompt."
                        )
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.dont.list")
                }
                
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Check it yourself").appText(.groupTitle)
                        .accessibilityIdentifier("privacy.verify.title")
                    
                    List {
                        PrivacyItem(
                            title: "Turn on Airplane Mode",
                            description: "CleanSlate works the same with Airplane Mode on. No network access is required."
                        )
                        
                        PrivacyItem(
                            title: "App Store listing",
                            description: "The App Store says \"Data Not Collected\" for CleanSlate."
                        )
                        
                        PrivacyItem(
                            title: "App Privacy Report",
                            description: "In Settings → Privacy & Security → App Privacy Report, you can see which apps used the network."
                        )
                    }
                    .listStyle(PlainListStyle())
                    .accessibilityIdentifier("privacy.verify.list")
                }
                
                Text("iCloud originals note").appText(.groupTitle)
                    .accessibilityIdentifier("privacy.icloud.title")
                
                Text("If you turn on *iCloud originals*, Photos downloads your own originals from iCloud so they can be checked. CleanSlate itself still sends nothing.")
                    .appText(.body)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, Spacing.s)
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Your privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyItem: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).appText(.groupTitle)
                .foregroundStyle(Color.textPrimary)
            Text(description).appText(.body)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    PrivacyView()
}