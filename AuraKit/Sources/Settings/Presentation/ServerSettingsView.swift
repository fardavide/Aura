import SwiftUI

import CommonDesign
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
            Section {
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
            } header: {
                Text("Server")
                    .auroraText(.sectionHeading)
                    .textCase(.uppercase)
                    .foregroundStyle(.auroraTextQuaternary)
            }
            .listRowBackground(Color.auroraSettingsRow)
            Section {
                TextField("Username", text: $viewModel.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("Password", text: $viewModel.password)
            } header: {
                Text("Authentication (optional)")
                    .auroraText(.sectionHeading)
                    .textCase(.uppercase)
                    .foregroundStyle(.auroraTextQuaternary)
            }
            .listRowBackground(Color.auroraSettingsRow)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).auroraText(.caption).foregroundStyle(.auroraLive)
            }
        }
        .formStyle(.grouped)
        .auroraText(.body)
        .scrollContentBackground(.hidden)
        .background(.auroraSettingsSheet)
        .safeAreaInset(edge: .bottom) {
            Button("Save") {
                viewModel.save()
                if viewModel.didSave { dismiss() }
            }
            .buttonStyle(.auroraGradient(glow: true))
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .navigationTitle("Server")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Server").auroraText(.headline)
            }
        }
        .onAppear { viewModel.onAppear() }
    }
}
