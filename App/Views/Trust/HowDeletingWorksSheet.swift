import SwiftUI

struct HowDeletingWorksSheet: View {
    let onDone: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("How deleting works").appText(.title)
                    .accessibilityIdentifier("deleting.title")
                
                VStack(alignment: .leading, spacing: Spacing.m) {
                    // Step 1
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("1").appText(.groupTitle)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Approve adds to your tray").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                    
                    // Step 2
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("2").appText(.groupTitle)
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("You delete from the tray").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                    
                    // Step 3
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("3").appText(.groupTitle)
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Apple asks you to confirm").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                }
                .padding(.bottom, Spacing.m)
                
                Text("Deleted photos stay in Recently Deleted for 30 days.").appText(.body)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, Spacing.s)
                
                NavigationLink("How to get photos back", destination: HowToRecoverSheet())
                    .appText(.body)
                    .foregroundStyle(Color.actionPrimary)
                    .accessibilityIdentifier("deleting.recover.link")
                    .buttonStyle(.plain)
            }
            .padding(Spacing.m)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.surfaceBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Got it") { onDone() }
                    .accessibilityIdentifier("deleting.ok")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deleting.sheet")
    }
}

struct HowToRecoverSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("How to get photos back").appText(.title)
                    .accessibilityIdentifier("recover.title")
                
                Text("If you accidentally delete a photo with CleanSlate, you can recover it from Recently Deleted in the Photos app:")
                    .appText(.body)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, Spacing.s)
                
                VStack(alignment: .leading, spacing: Spacing.m) {
                    // Step 1
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("1").appText(.groupTitle)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Open the Photos app").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                    
                    // Step 2
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("2").appText(.groupTitle)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Tap the \"Recently Deleted\" tab at the bottom").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                    
                    // Step 3
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("3").appText(.groupTitle)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Select the photo(s) you want to recover").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                    
                    // Step 4
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("4").appText(.groupTitle)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.actionPrimary.opacity(0.1))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        
                        Text("Tap \"Recover\"").appText(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .contain)
                }
                .padding(.bottom, Spacing.m)
                
                Text("After 30 days, or after you empty Recently Deleted, photos can't be recovered.").appText(.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.m)
        }
        .navigationTitle("How to get photos back")
        .navigationBarTitleDisplayMode(.inline)
        .presentationDetents([.medium])
        .presentationBackground(Color.surfaceBackground)
    }
}

#Preview {
    HowDeletingWorksSheet(onDone: {})
}