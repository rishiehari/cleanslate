import Foundation

/// Applying a batch of library changes to the index. Shared by the scan and by live invalidation.
@MainActor
enum LibrarySync {
    enum Meta {
        static let token = "library.changeToken"
        static let complete = "inventory.complete"
        static let offset = "inventory.offset"
        static let startedAt = "inventory.startedAt"
        static let startToken = "inventory.startToken"
    }

    /// Re-reads every changed asset, stores it, forgets the deleted ones and advances the saved token.
    /// Returns how many assets were touched.
    @discardableResult
    static func apply(_ set: LibraryChangeSet, library: PhotoLibraryClient, store: LibraryStore) async -> Int {
        var upserts: [PhotoSnapshot] = []
        var vanished = set.deletedIDs
        for id in set.changedIDs {
            if let photo = library.snapshot(id: id, inspectAlbums: false) { upserts.append(photo) }
            else { vanished.insert(id) }          // no longer fetchable (removed or hidden)
        }
        try? await store.upsert(upserts)
        try? await store.markDeleted(Array(vanished))
        try? await store.setMeta(Meta.token, set.newToken)
        return upserts.count + vanished.count
    }
}
