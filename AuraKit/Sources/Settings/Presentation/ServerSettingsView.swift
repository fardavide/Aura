import SwiftUI

import CommonDesign
import SettingsDomain

/// Edits the addresses and shared credentials for one Frigate server.
public struct ServerSettingsView: View {
    public enum Completion {
        case save(() -> Void)
        case connect(() -> Void)
    }

    @State private var viewModel: ServerSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    private let completion: Completion

    public init(viewModel: ServerSettingsViewModel, completion: Completion = .save({})) {
        _viewModel = State(initialValue: viewModel)
        self.completion = completion
    }

    public var body: some View {
        Form {
            Section {
                addressField("Local address", example: "http://192.168.1.50:5000", address: $viewModel.localAddress)
                addressField("Remote address", example: "https://frigate.example.net", address: $viewModel.remoteAddress)
            } header: {
                Text("One address is enough.")
                    .auroraText(.headline)
                    .foregroundStyle(.auroraTextPrimary)
                    .textCase(nil)
            } footer: {
                if viewModel.saveError == .missingAddress, let errorMessage = viewModel.errorMessage {
                    Label {
                        Text(errorMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.auroraLive)
                    }
                    .auroraText(.caption)
                    .foregroundStyle(.auroraTextPrimary)
                } else {
                    sectionFooter("With two addresses, Aura tries local first and switches to remote if needed.")
                }
            }
            .listRowBackground(Color.auroraSettingsRow)
            Section {
                liveFields("Local", scheme: $viewModel.localLiveScheme, port: $viewModel.localLivePort)
                liveFields("Remote", scheme: $viewModel.remoteLiveScheme, port: $viewModel.remoteLivePort)
            } header: {
                sectionHeading("Live streaming")
            } footer: {
                sectionFooter("Clear a live port to use the Frigate proxy for that address.")
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
                sectionHeading("Authentication (optional)")
            } footer: {
                sectionFooter("These credentials apply to both addresses and the Frigate proxy.")
            }
            .listRowBackground(Color.auroraSettingsRow)
        }
        .formStyle(.grouped)
        .auroraText(.body)
        .scrollContentBackground(.hidden)
        .background(.auroraSettingsSheet)
        .safeAreaInset(edge: .bottom) {
            if viewModel.saveError != .missingAddress, let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .auroraText(.caption)
                    .foregroundStyle(.auroraLive)
                    .multilineTextAlignment(.center)
                    .padding(16)
            }
        }
        .navigationTitle("Server")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Server").auroraText(.headline)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    Text("Save").auroraText(.headline)
                }
            }
        }
        .animation(.default, value: viewModel.errorMessage)
        .onAppear { viewModel.onAppear() }
    }

    private func save() {
        viewModel.save()
        guard viewModel.didSave else { return }
        switch completion {
        case .save(let onSaved):
            onSaved()
            dismiss()
        case .connect(let onConnect):
            onConnect()
        }
    }

    private func addressField(_ title: String, example: String, address: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeading(title)
            TextField(title, text: address, prompt: Text(example))
                .textFieldStyle(.automatic)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func liveFields(_ route: String, scheme: Binding<ServerAddress.Scheme>, port: Binding<String>) -> some View {
        Picker("\(route) scheme", selection: scheme) {
            ForEach(ServerAddress.Scheme.allCases, id: \.self) { scheme in
                Text(scheme.rawValue.uppercased()).tag(scheme)
            }
        }
        .pickerStyle(.menu)
        LabeledContent("\(route) port") {
            TextField("\(route) live port", text: port, prompt: Text("Frigate proxy"))
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .auroraText(.sectionHeading)
            .textCase(.uppercase)
            .foregroundStyle(.auroraTextQuaternary)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .auroraText(.caption)
            .foregroundStyle(.auroraTextQuaternary)
    }
}
