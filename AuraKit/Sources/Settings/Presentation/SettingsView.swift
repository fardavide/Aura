import SwiftUI

import SettingsDomain

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    /// `nil` before a connection is configured (first run) — the reorder screen
    /// needs a server to list cameras from, so its row is hidden until then.
    private let makeCameraOrderViewModel: (() -> CameraOrderViewModel)?
    private let onDone: () -> Void

    public init(
        viewModel: SettingsViewModel,
        makeCameraOrderViewModel: (() -> CameraOrderViewModel)?,
        onDone: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.makeCameraOrderViewModel = makeCameraOrderViewModel
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Picker("Scheme", selection: $viewModel.scheme) {
                        ForEach(ConnectionSettings.Scheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue.uppercased()).tag(scheme)
                        }
                    }
                    TextField("Host", text: $viewModel.host)
                        .textFieldStyle(.automatic)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Port", text: $viewModel.port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section("Authentication (optional)") {
                    TextField("Username", text: $viewModel.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    SecureField("Password", text: $viewModel.password)
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
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Save") {
                    viewModel.save()
                    if viewModel.didSave { onDone() }
                }
            }
            .onAppear { viewModel.onAppear() }
        }
    }
}
