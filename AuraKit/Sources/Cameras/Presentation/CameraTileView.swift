import SwiftUI

import CamerasDomain

struct CameraTileView: View {
    let camera: Camera
    let loadImage: (Camera) async -> Data?

    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "video.slash").foregroundStyle(.secondary))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) {
            Text(camera.friendlyName ?? camera.name.value)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(8)
        }
        .task(id: camera.id) {
            image = await loadImage(camera).flatMap(platformImage(from:))
        }
    }
}
