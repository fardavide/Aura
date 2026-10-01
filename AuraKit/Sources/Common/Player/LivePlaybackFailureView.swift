import SwiftUI

import CommonDesign

public struct LivePlaybackFailureView: View {
    private let retry: () -> Void

    public init(retry: @escaping () -> Void) {
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "video.slash")
                .font(.system(size: 44))
                .foregroundStyle(.auroraTextTertiary)
                .padding(.bottom, 6)
            Text("Live stream unavailable")
                .auroraText(.headline)
                .foregroundStyle(.auroraTextPrimary)
            Text("Check the live port in Server settings, then try again.")
                .auroraText(.body)
                .foregroundStyle(.auroraTextTertiary)
            Button("Retry", action: retry)
                .buttonStyle(.auroraGradient)
                .padding(.top, 15)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
