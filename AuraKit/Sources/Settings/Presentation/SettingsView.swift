import SwiftUI

import SettingsDomain

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let makeServerSettingsViewModel: () -> ServerSettingsViewModel
    /// `nil` before a connection is configured (first run) — the reorder screen
    /// needs a server to list cameras from, so its row is hidden until then.
    private let makeCameraOrderViewModel: (() -> CameraOrderViewModel)?
    /// `nil` where the platform has no swappable app icon, which hides the row on macOS.
    private let makeAppIconViewModel: (() -> AppIconViewModel)?
    private let onDone: () -> Void

    public init(
        viewModel: SettingsViewModel,
        makeServerSettingsViewModel: @escaping () -> ServerSettingsViewModel,
        makeCameraOrderViewModel: (() -> CameraOrderViewModel)?,
        makeAppIconViewModel: (() -> AppIconViewModel)?,
        onDone: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.makeServerSettingsViewModel = makeServerSettingsViewModel
        self.makeCameraOrderViewModel = makeCameraOrderViewModel
        self.makeAppIconViewModel = makeAppIconViewModel
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Server") {
                        ServerSettingsView(viewModel: makeServerSettingsViewModel())
                    }
                }
                if let makeCameraOrderViewModel {
                    Section("Cameras") {
                        NavigationLink("Camera Order") {
                            CameraOrderView(viewModel: makeCameraOrderViewModel())
                        }
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(ThemePreference.allCases, id: \.self) { theme in
                            Text(theme.rawValue.capitalized).tag(theme)
                        }
                    }
                    if let makeAppIconViewModel {
                        NavigationLink("App Icon") {
                            AppIconView(viewModel: makeAppIconViewModel())
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                Button("Done", action: onDone)
            }
            .onAppear { viewModel.onAppear() }
        }
    }
}
