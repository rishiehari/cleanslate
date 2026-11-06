import SwiftUI

struct PhotoThumbnailView: View {
    @Environment(\.photoLibrary) private var library
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
            image = await library.thumbnail(assetID, target: target)
            finished = true
        }
        .accessibilityLabel(image == nil ? "Photo thumbnail unavailable" : "Photo preview")
    }
}
