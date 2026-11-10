import Foundation
import XCTest
@testable import CleanSlate

/// Builds a view model on in-memory storage with a fake library, fake Vision and a governor that never pauses.
@MainActor
enum ScanTestRig {
    static func governor(cores: Int = 8) -> ResourceGovernor {
        ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { 1_000_000_000 },
                                       lowPowerMode: { false }, sleep: { _ in }), cores: cores, maximumPauseSeconds: 0)
    }

    static func model(library: FakePhotoLibrary, visual: VisualAnalyzing = FakeVisualAnalyzer(),
                      tray: DeletionTray = DeletionTray(fileURL: nil), store: LibraryStore? = nil,
                      governor: ResourceGovernor? = nil, diagnostics: DiagnosticsLog? = nil) throws -> CleaningViewModel {
        CleaningViewModel(library: library, tray: tray,
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "rig.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: try store ?? LibraryStore(path: nil), governor: governor ?? Self.governor(), visual: visual,
                          diagnostics: diagnostics)
    }
}
