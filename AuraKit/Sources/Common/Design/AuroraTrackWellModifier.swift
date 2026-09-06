import SwiftUI

extension View {
    public func auroraTrackWell(cornerRadius: CGFloat = AuroraTrack.wellCornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background { shape.fill(Color.auroraWell.shadow(.inner(color: .black.opacity(0.35), radius: 1, y: 1))) }
            .clipShape(shape)
    }
}
