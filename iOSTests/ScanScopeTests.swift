import XCTest
@testable import CleanSlate

class ScanScopeTests: XCTestCase {
    
    func testScanScopeCalculation() {
        // Test that each scan scope calculates max items correctly
        XCTAssertEqual(ScanScope.recent100.calculateMaxItems(for: 50), 50) // Less than limit
        XCTAssertEqual(ScanScope.recent100.calculateMaxItems(for: 150), 100) // More than limit
        
        XCTAssertEqual(ScanScope.next1000.calculateMaxItems(for: 500), 500) // Less than limit
        XCTAssertEqual(ScanScope.next1000.calculateMaxItems(for: 1500), 1000) // More than limit
        
        XCTAssertEqual(ScanScope.start2000.calculateMaxItems(for: 500), 500) // Less than limit
        XCTAssertEqual(ScanScope.start2000.calculateMaxItems(for: 3000), 2000) // More than limit
        
        XCTAssertEqual(ScanScope.all.calculateMaxItems(for: 10000), 10000) // Full library
    }
    
    func testScanScopeDescriptions() {
        XCTAssertEqual(ScanScope.recent100.description, "Quick preview scan of recent photos")
        XCTAssertEqual(ScanScope.next1000.description, "Medium scan of next 1,000 photos")
        XCTAssertEqual(ScanScope.start2000.description, "Standard scan of first 2,000 photos")
        XCTAssertEqual(ScanScope.album.description, "Scan a specific album")
        XCTAssertEqual(ScanScope.all.description, "Full library scan (not recommended for large libraries)")
    }
    
    func testPhotoStatusIcons() {
        XCTAssertEqual(PhotoStatus.local.icon, "📱")
        XCTAssertEqual(PhotoStatus.cloudOnly.icon, "☁️")
        XCTAssertEqual(PhotoStatus.unknown.icon, "❓")
    }
}