import SwiftUI

struct ScanProgressCard: View {
    @State private var isStalled = false
    @State private var stallTimer: Timer?
    
    let snapshot: ScanProgressSnapshot
    
    var body: some View {
        if snapshot.isScanning {
            CardView {
                VStack(alignment: .leading, spacing: 8) {
                    // Stage name
                    Text(stageName)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    
                    // Progress bar
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .accessibilityValue("\(Int(progressValue * 100)) percent")
                    
                    // Count and ETA
                    HStack {
                        Text(countText)
                            .font(.body)
                        
                        Spacer()
                        
                        if let eta = snapshot.eta, !isStalled {
                            Text("· about \(formatDuration(eta)) left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !isStalled {
                            // We don't have elapsed time in the snapshot, so we'll show a generic message
                            Text("Elapsed time is hidden during scan")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Found so far
                    HStack {
                        Text(foundText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .onTapGesture {
                                // Jump to the category list
                                // This would be implemented with navigation logic
                            }
                        
                        Spacer()
                        
                        if snapshot.lastBeatAt != nil {
                            Image(systemName: "waveform.path.ecg")
                                .symbolEffect(.pulse, options: .speed(0.5))
                                .foregroundColor(.blue)
                                .accessibilityHidden(true)
                        }
                    }
                    
                    // Stalled message
                    if isStalled {
                        Text("This is taking longer than usual. It's safe to leave; CleanSlate picks up where it stopped.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        HStack(spacing: 12) {
                            Button("Skip this step") {
                                // Skip the current stage
                                // This would be implemented with actual logic
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Keep waiting") {
                                // Continue waiting
                                resetStallTimer()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Pause/Stop buttons (always visible)
                    HStack(spacing: 12) {
                        Button("Pause") {
                            // Pause the scan
                            // This would be implemented with actual logic
                        }
                        .buttonStyle(.glass)
                        
                        Button("Stop") {
                            // Stop the scan
                            // This would be implemented with actual logic
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .onAppear {
                startStallTimer()
            }
            .onDisappear {
                stallTimer?.invalidate()
            }
        }
    }
    
    private var stageName: String {
        switch snapshot.stage {
        case .reading:
            return "Reading your photos"
        case .comparing:
            return "Comparing"
        case .grouping:
            return "Grouping"
        }
    }
    
    private var progressValue: Double {
        guard snapshot.stageTotal > 0 else { return 0 }
        return Double(snapshot.stageDone) / Double(snapshot.stageTotal)
    }
    
    private var countText: String {
        "\(snapshot.stageDone) of \(snapshot.stageTotal)"
    }
    
    private var foundText: String {
        if snapshot.foundExactGroups > 0 || snapshot.foundSimilarGroups > 0 {
            return "Found \(snapshot.foundExactGroups) sets of copies (\(formatBytes(snapshot.foundVerifiedBytes))) and \(snapshot.foundSimilarGroups) similar sets"
        } else {
            return "Found 0 sets"
        }
    }
    
    private func formatDuration(_ duration: Duration) -> String {
        let minutes = Int(duration.components.seconds / 60)
        if minutes < 1 {
            return "less than a minute"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        } else if bytes < 1024 * 1024 * 1024 {
            return "\(bytes / (1024 * 1024)) MB"
        } else {
            return "\(bytes / (1024 * 1024 * 1024)) GB"
        }
    }
    
    private func startStallTimer() {
        stallTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let lastBeat = snapshot.lastBeatAt {
                let elapsed = ContinuousClock.now.duration(to: lastBeat)
                isStalled = elapsed > .seconds(20)
            }
        }
    }
    
    private func resetStallTimer() {
        stallTimer?.invalidate()
        startStallTimer()
    }
}

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            content
        }
        .padding(.horizontal)
    }
}

#Preview {
    ScanProgressCard(snapshot: ScanProgressSnapshot(
        phase: .inventory,
        done: 84,
        total: 100,
        foundGroups: 3,
        foundBytesVerified: 12_400_000,
        pauseReason: nil,
        isStalled: false,
        startedAt: Date(),
        stage: .reading,
        stageDone: 84,
        stageTotal: 100,
        foundExactGroups: 3,
        foundSimilarGroups: 5,
        foundVerifiedBytes: 12_400_000,
        lastBeatAt: ContinuousClock.now,
        eta: .seconds(120),
        isScanning: true
    ))
}