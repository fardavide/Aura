import SwiftUI

import SettingsDomain

/// Pushed from the main settings screen; Save persists the connection and pops back.
public struct ServerSettingsView: View {
    @State private var viewModel: ServerSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ServerSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
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
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Server")
        .toolbar {
            Button("Save") {
                viewModel.save()
                if viewModel.didSave { dismiss() }
            }
        }
        .onAppear { viewModel.onAppear() }
    }
}
