import Foundation
import Network
import CleanSlateCore

/// The ONLY place that may allow downloading originals from iCloud (opt-in, Wi-Fi only, budgeted).
/// Everything else in the app reads local data only.
@MainActor
final class NetworkPolicy: ObservableObject {
    static let shared = NetworkPolicy()
    static let enabledKey = "verifyICloud.enabled"
    static let budgetKey = "verifyICloud.budgetGB"
    static let budgetChoicesGB = [1, 2, 5, 10]

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Self.enabledKey) } }
    @Published var budgetGB: Int { didSet { defaults.set(budgetGB, forKey: Self.budgetKey) } }
    @Published private(set) var downloadedBytes: Int64 = 0

    private let defaults: UserDefaults
    private let pathCheck: () -> Bool
    private let monitor = NWPathMonitor()
    private var latestPath: NWPath?

    /// `pathCheck` is a test seam: return true when the connection is acceptable (not cellular, not constrained).
    init(defaults: UserDefaults = .standard, pathCheck: (() -> Bool)? = nil) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        let stored = defaults.integer(forKey: Self.budgetKey)
        self.budgetGB = Self.budgetChoicesGB.contains(stored) ? stored : 2
        // Production: unknown connection == not allowed, until the monitor reports a real path.
        self.pathCheck = pathCheck ?? { false }
        if pathCheck == nil {
            monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.latestPath = path } }
            monitor.start(queue: DispatchQueue(label: "org.cleanslate.networkpolicy"))
        }
    }

    deinit { monitor.cancel() }

    var budgetBytes: Int64 { Int64(budgetGB) * 1_000_000_000 }
    var remainingBytes: Int64 { max(0, budgetBytes - downloadedBytes) }

    private var connectionIsAcceptable: Bool {
        guard let path = latestPath else { return pathCheck() }
        return path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }

    func allowsOriginalDownload() -> Bool {
        isEnabled && downloadedBytes < budgetBytes && connectionIsAcceptable
    }

    func record(downloadedBytes bytes: Int64) { downloadedBytes += max(0, bytes) }
    func resetSessionBudget() { downloadedBytes = 0 }
}

/// Reads originals locally first; downloads only when `NetworkPolicy` allows it.
/// Used by the SCAN only. The commit-time recheck is always local-only (no surprise downloads mid-deletion).
@MainActor
struct DigestFetcher {
    let library: PhotoLibraryClient
    let policy: NetworkPolicy

    struct Result { let digests: [ResourceDigest]; let downloaded: Bool }

    /// `estimatedBytes` lets the budget refuse an asset that clearly won't fit, and charges the
    /// estimate when a download fails part-way (so repeated failures can't use unlimited data).
    func fetch(id: String, estimatedBytes: Int64 = 0) async throws -> Result {
        do {
            return Result(digests: try await library.digests(id: id, allowNetwork: false), downloaded: false)
        } catch let error as LibraryResourceError where error == .notAccessible || error == .empty {
            guard policy.allowsOriginalDownload(), estimatedBytes <= policy.remainingBytes else { throw error }
            do {
                let digests = try await library.digests(id: id, allowNetwork: true)
                policy.record(downloadedBytes: digests.reduce(Int64(0)) { $0 + $1.byteCount })
                return Result(digests: digests, downloaded: true)
            } catch {
                let cancelled = error is CancellationError || (error as? LibraryResourceError) == .cancelled
                if !cancelled { policy.record(downloadedBytes: estimatedBytes) }   // a user's Stop isn't a failed download
                throw error
            }
        }
    }
}
