import XCTest
@testable import CleanSlate

final class EtaEstimatorTests: XCTestCase {
    
    func testEtaEstimatorInitial() {
        var estimator = EtaEstimator()
        XCTAssertNil(estimator.estimate)
    }
    
    func testEtaEstimatorStable() {
        var estimator = EtaEstimator(minimumSamples: 2, minimumElapsed: .seconds(1))
        
        // Add some samples
        let now = ContinuousClock.now
        estimator.record(done: 10, total: 100, at: now)
        estimator.record(done: 20, total: 100, at: now.advanced(by: .seconds(2)))
        estimator.record(done: 30, total: 100, at: now.advanced(by: .seconds(4)))
        estimator.record(done: 40, total: 100, at: now.advanced(by: .seconds(6)))
        
        // Should have a stable estimate now
        XCTAssertNotNil(estimator.estimate)
        XCTAssertTrue(estimator.estimate! > .zero)
    }
    
    func testEtaEstimatorUnstable() {
        var estimator = EtaEstimator(minimumSamples: 5, minimumElapsed: .seconds(10))
        
        // Add some samples that are not stable
        let now = ContinuousClock.now
        estimator.record(done: 10, total: 100, at: now)
        estimator.record(done: 20, total: 100, at: now.advanced(by: .seconds(2)))
        estimator.record(done: 30, total: 100, at: now.advanced(by: .seconds(5)))
        
        // Should not be stable yet
        XCTAssertNil(estimator.estimate)
    }
    
    func testEtaEstimatorTooLong() {
        var estimator = EtaEstimator()
        
        let now = ContinuousClock.now
        estimator.record(done: 10, total: 100, at: now)
        estimator.record(done: 20, total: 100, at: now.advanced(by: .seconds(1000))) // Very long time
        
        // Should be nil because it's over 3 hours
        XCTAssertNil(estimator.estimate)
    }
}