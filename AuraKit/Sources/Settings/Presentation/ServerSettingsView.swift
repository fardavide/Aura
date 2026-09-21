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
                addressFields(
                    scheme: $viewModel.remoteScheme,
                    host: $viewModel.remoteHost,
                    port: $viewModel.remotePort
                )
            } header: {
                sectionHeading("Remote address")
            } footer: {
                sectionFooter("Reachable from anywhere — over Tailscale, a VPN or a domain name. Used whenever the local address doesn't answer.")
            }
            .listRowBackground(Color.auroraSettingsRow)
            Section {
                addressFields(
                    scheme: $viewModel.localScheme,
                    host: $viewModel.localHost,
                    port: $viewModel.localPort
                )
            } header: {
                sectionHeading("Local address (optional)")
            } footer: {
                sectionFooter("Your server's address on your home network. Aura uses it automatically whenever you're on Wi-Fi and it answers, and falls back to the remote address otherwise. Leave the host empty to always use the remote address.")
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
                sectionFooter("The same credentials are used for both addresses — they reach the same server.")
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

    @ViewBuilder
    private func addressFields(
        scheme: Binding<ServerAddress.Scheme>,
        host: Binding<String>,
        port: Binding<String>
    ) -> some View {
        Picker("Scheme", selection: scheme) {
            ForEach(ServerAddress.Scheme.allCases, id: \.self) { scheme in
                Text(scheme.rawValue.uppercased()).tag(scheme)
            }
        }
        TextField("Host", text: host)
            .textFieldStyle(.automatic)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
        TextField("Port", text: port)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
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
