import SwiftUI

import CommonDesign
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
                    NavigationLink {
                        ServerSettingsView(viewModel: makeServerSettingsViewModel())
                    } label: {
                        SettingsMenuRow(title: "Server", value: serverValue)
                    }
                } footer: {
                    if viewModel.serverSummary == .notConfigured {
                        Text("Add a server to continue")
                            .auroraText(.caption)
                            .foregroundStyle(.auroraTextQuaternary)
                    }
                }
                .listRowBackground(Color.auroraSettingsRow)
                if let makeCameraOrderViewModel {
                    Section {
                        NavigationLink {
                            CameraOrderView(viewModel: makeCameraOrderViewModel())
                        } label: {
                            SettingsMenuRow(title: "Camera Order", value: viewModel.cameraCountText)
                        }
                    } header: {
                        Text("Cameras")
                            .auroraText(.sectionHeading)
                            .textCase(.uppercase)
                            .foregroundStyle(.auroraTextQuaternary)
                    }
                    .listRowBackground(Color.auroraSettingsRow)
                }
                Section {
                    LabeledContent {
                        AuroraSegmentedControl(
                            options: ThemePreference.allCases,
                            selection: $viewModel.theme,
                            container: .well
                        ) { $0.rawValue.capitalized }
                    } label: {
                        Text("Theme").auroraText(.headline).foregroundStyle(.auroraTextPrimary)
                    }
                    if let makeAppIconViewModel {
                        NavigationLink {
                            AppIconView(viewModel: makeAppIconViewModel())
                        } label: {
                            SettingsMenuRow(title: "App Icon", value: viewModel.appIcon?.rawValue.capitalized) {
                                if let appIcon = viewModel.appIcon {
                                    Image(decorative: "AppIconPreview-\(appIcon.rawValue)")
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Appearance")
                        .auroraText(.sectionHeading)
                        .textCase(.uppercase)
                        .foregroundStyle(.auroraTextQuaternary)
                }
                .listRowBackground(Color.auroraSettingsRow)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color.auroraSettingsSheet
                    settingsSheetHeadWashes
                    AuroraGlow().frame(height: 360).padding(.top, 140)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings").auroraText(.headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onDone()
                    } label: {
                        Text("Done").auroraText(.headline)
                    }
                    .disabled(viewModel.serverSummary == .notConfigured)
                }
            }
            .onAppear { viewModel.onAppear() }
            .task { await viewModel.load() }
        }
    }

    private var serverValue: String {
        switch viewModel.serverSummary {
        case .notConfigured: "Not configured"
        case let .configured(hostPort): hostPort
        }
    }
}

/// The mock's two sheet-head radials (mock L234) — the same tokens and geometry
/// `AuroraBackground` uses for its own washes, reproduced here because the sheet paints its own
/// background rather than sharing the tab roots' `.auroraBackground()`.
private var settingsSheetHeadWashes: some View {
    GeometryReader { geo in
        ZStack {
            wash(.auroraWashViolet, width: 0.70, height: 0.38, at: UnitPoint(x: 0.15, y: 0.00), in: geo.size)
            wash(.auroraWashPink, width: 0.60, height: 0.34, at: UnitPoint(x: 0.92, y: 0.06), in: geo.size)
        }
    }
}

private func wash(_ color: Color, width: CGFloat, height: CGFloat, at center: UnitPoint, in size: CGSize) -> some View {
    EllipticalGradient(colors: [color, .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        .frame(width: size.width * width * 2, height: size.height * height * 2)
        .position(x: size.width * center.x, y: size.height * center.y)
}
