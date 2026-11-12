import SwiftUI

struct PhotoThumbnailView: View {
    @Environment(\.photoLibraryOverride) private var override
    private var library: PhotoLibraryClient { override ?? PhotoKitLibraryClient.shared }
    let assetID: String
    var target: CGFloat = 280
    var fill = false
    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.s).fill(Color.surfaceCard)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Image(systemName: finished ? "icloud.slash" : "photo")
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: assetID) {
            finished = false
            image = nil
            let loaded = await library.thumbnail(assetID, target: min(target, 1_400))
            guard !Task.isCancelled else { return }
            image = loaded
            finished = true
        }
        .accessibilityLabel(image != nil ? "Photo preview" : finished ? "Photo thumbnail unavailable" : "Loading photo preview")
    }
}
