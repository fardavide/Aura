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
                    port: $viewModel.remotePort,
                    liveScheme: $viewModel.remoteLiveScheme,
                    livePort: $viewModel.remoteLivePort
                )
            } header: {
                sectionHeading("Remote address")
            } footer: {
                sectionFooter("Reachable from anywhere — over Tailscale, a VPN or a domain name. Used whenever the local address doesn't answer. Live video uses this host with its own scheme and port, defaulting to HTTP on port 1984 for new setups. Clear the live port to use the Frigate proxy on older servers.")
            }
            .listRowBackground(Color.auroraSettingsRow)
            Section {
                addressFields(
                    scheme: $viewModel.localScheme,
                    host: $viewModel.localHost,
                    port: $viewModel.localPort,
                    liveScheme: $viewModel.localLiveScheme,
                    livePort: $viewModel.localLivePort
                )
            } header: {
                sectionHeading("Local address (optional)")
            } footer: {
                sectionFooter("Your server's address on your home network. Aura prefers it when it answers. Leave the host empty to always use the remote address. Live video uses this local host, defaulting to HTTP on port 1984 for new addresses. Its port can differ from the remote one. Clear the live port to use the Frigate proxy.")
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
                sectionFooter("These credentials apply to both Frigate API addresses and their live proxy. Direct live playback never receives them.")
            }
            .listRowBackground(Color.auroraSettingsRow)
        }
        .formStyle(.grouped)
        .auroraText(.body)
        .scrollContentBackground(.hidden)
        .background(.auroraSettingsSheet)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).auroraText(.caption).foregroundStyle(.auroraLive)
                }
                Button("Save") {
                    viewModel.save()
                    if viewModel.didSave { dismiss() }
                }
                .buttonStyle(.auroraGradient(glow: true))
                .frame(maxWidth: .infinity)
            }
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
        port: Binding<String>,
        liveScheme: Binding<ServerAddress.Scheme>,
        livePort: Binding<String>
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
        Picker("Live scheme", selection: liveScheme) {
            ForEach(ServerAddress.Scheme.allCases, id: \.self) { scheme in
                Text(scheme.rawValue.uppercased()).tag(scheme)
            }
        }
        TextField("Live port (optional)", text: livePort)
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
