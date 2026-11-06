import XCTest
import MachO
import CleanSlateCore
@testable import CleanSlate

/// Scale harness on the fake library. Default size keeps CI fast; set CLEANSLATE_SCALE_N=250000 for the full run.
@MainActor
final class ScaleTests: XCTestCase {
    private func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    func testLargeLibraryInventoryAndExactPairsStayFastAndComplete() async throws {
        let size = ProcessInfo.processInfo.environment["CLEANSLATE_SCALE_N"].flatMap(Int.init) ?? 40_000
        let planted = 1_200                                     // 2,400 members: under the per-scan hashing cap
        let library = FakePhotoLibrary()
        library.disableThumbnails = true                         // pixel work is measured on a device; this measures the engine
        library.addBulk(count: size, plantedExactPairs: planted)
        let store = try LibraryStore(path: nil)
        let model = CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                                      networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "scale.\(UUID().uuidString)")!, pathCheck: { false }),
                                      store: store)
        let memoryBefore = residentMegabytes()
        let start = Date()
        await model.runScan()
        let seconds = Date().timeIntervalSince(start)
        let memoryGrowth = residentMegabytes() - memoryBefore

        let total = size + planted * 2
        XCTAssertEqual(model.statistics.photosEnumerated, total)
        XCTAssertEqual(model.groups(in: .exact).count, planted, "every planted pair is found (recall 100%)")
        XCTAssertEqual(model.statistics.exactSkippedByLimit, 0)
        print("SCALE n=\(total) seconds=\(String(format: "%.1f", seconds)) residentGrowthMB=\(String(format: "%.0f", memoryGrowth)) pages=\(library.pageRequests.count)")
        // Budgets scale linearly from the plan's 250k numbers (60 s inventory, 300 MB).
        let scaled = Double(total) / 250_000
        XCTAssertLessThan(seconds, max(20, 150 * scaled), "scan took \(seconds)s for \(total) assets")
        XCTAssertLessThan(memoryGrowth, max(250, 450 * scaled), "memory grew \(memoryGrowth) MB")
    }

    func testRelaunchOnALargeIndexIsIncrementalAndInstant() async throws {
        let library = FakePhotoLibrary()
        library.disableThumbnails = true
        library.addBulk(count: 20_000, plantedExactPairs: 0)
        let store = try LibraryStore(path: nil)
        func makeModel() -> CleaningViewModel {
            CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                              networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "scale.\(UUID().uuidString)")!, pathCheck: { false }),
                              store: store)
        }
        library.recordChange(changed: ["bulk1"])                 // gives the fake a token to hand out
        await makeModel().runScan()
        let pages = library.pageRequests.count
        let start = Date()
        let second = makeModel(); await second.runScan()
        XCTAssertEqual(second.statistics.inventoryMode, .incremental)
        XCTAssertEqual(library.pageRequests.count, pages, "a second scan never re-walks the library")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
