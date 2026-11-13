import SwiftUI

struct ScanStatusCard: View {
    let snapshot: ScanProgressSnapshot
    
    var body: some View {
        if !snapshot.isScanning {
            // Only show idle/finished states here
            CardView {
                VStack(spacing: 8) {
                    Text("Scan complete")
                        .font(.headline)
                    
                    Text("Found \(snapshot.foundExactGroups) exact groups and \(snapshot.foundSimilarGroups) similar groups")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        // When scanning, ScanProgressCard is used instead
    }
}

#Preview {
    ScanStatusCard(snapshot: ScanProgressSnapshot(
        phase: .idle,
        done: 100,
        total: 100,
        foundGroups: 3,
        foundBytesVerified: 12_400_000,
        pauseReason: nil,
        isStalled: false,
        startedAt: Date(),
        stage: .reading,
        stageDone: 100,
        stageTotal: 100,
        foundExactGroups: 3,
        foundSimilarGroups: 5,
        foundVerifiedBytes: 12_400_000,
        lastBeatAt: ContinuousClock.now,
        eta: nil,
        isScanning: false
    ))
}