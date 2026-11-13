import Foundation

struct EtaEstimator {
    private let minimumSamples: Int
    private let minimumElapsed: Duration
    private var samples: [(done: Int, total: Int, at: ContinuousClock.Instant)] = []
    
    init(minimumSamples: Int = 20, minimumElapsed: Duration = .seconds(10)) {
        self.minimumSamples = minimumSamples
        self.minimumElapsed = minimumElapsed
    }
    
    mutating func record(done: Int, total: Int, at: ContinuousClock.Instant) {
        samples.append((done: done, total: total, at: at))
    }
    
    var estimate: Duration? {
        // Need at least minimumSamples units and minimumElapsed time
        guard samples.count >= minimumSamples,
              let first = samples.first,
              let last = samples.last,
              last.at.duration(to: first.at) >= minimumElapsed else {
            return nil
        }
        
        // Calculate the average rate over the last few samples
        var totalDuration: Duration = .zero
        var totalDone: Int = 0
        
        // Take the last 3 samples for stability check
        let recentSamples = Array(samples.suffix(3))
        
        guard recentSamples.count == 3 else { return nil }
        
        // Check if estimates are within ±25% of each other
        var rates: [Double] = []
        for i in 1..<recentSamples.count {
            let sample = recentSamples[i]
            let prevSample = recentSamples[i - 1]
            
            let timeDiff = sample.at.duration(to: prevSample.at)
            let doneDiff = sample.done - prevSample.done
            
            guard timeDiff > .zero, doneDiff > 0 else { continue }
            
            // Rate in units per second
            rates.append(Double(doneDiff) / Double(timeDiff.components.seconds))
        }
        
        guard rates.count == 2 else { return nil }
        
        let averageRate = rates.reduce(0, +) / Double(rates.count)
        
        // Check stability - rates should be within ±25% of each other
        let rateRange = rates.max()! - rates.min()!
        let rateRatio = rateRange / averageRate
        
        guard rateRatio <= 0.25 else { return nil }
        
        // Calculate remaining time based on the current average rate
        let remainingUnits = samples.last!.total - samples.last!.done
        guard remainingUnits > 0, averageRate > 0 else { return nil }
        
        let remainingSeconds = Double(remainingUnits) / averageRate
        let remainingTime = Duration(secondsComponent: Int64(remainingSeconds), attosecondsComponent: 0)
        
        // Cap at 3 hours (3 * 3600 seconds)
        guard remainingTime.components.seconds < 10800 else { return nil }
        
        // Round up to nearest minute
        let roundedMinutes = Int64(ceil(Double(remainingTime.components.seconds) / 60.0))
        return Duration(secondsComponent: roundedMinutes * 60, attosecondsComponent: 0)
    }
}

// Extension to safely access array elements by index
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}