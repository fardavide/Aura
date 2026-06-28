import SwiftUI

@main
struct AuraApp: App {
    @State private var composition = AppComposition()

    var body: some Scene {
        WindowGroup {
            RootView(composition: composition)
        }
    }
}
