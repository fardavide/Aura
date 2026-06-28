import SwiftUI
#if os(iOS)
import AVFoundation
#endif

@main
struct AuraApp: App {
    @State private var composition = AppComposition()

    init() {
        #if os(iOS)
        // .playback keeps live audio going in the background and enables Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(composition: composition)
        }
    }
}
