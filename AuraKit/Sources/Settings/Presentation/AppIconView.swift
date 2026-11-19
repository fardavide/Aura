import SwiftUI

import CommonDesign
import SettingsDomain

public struct AppIconView: View {
    private let viewModel: AppIconViewModel

    public init(viewModel: AppIconViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.usesSeasonalIcons },
                    set: { isEnabled in Task { await viewModel.setSeasonalIcons(isEnabled) } }
                )) {
                    Text("Seasonal Icons")
                        .auroraText(.headline)
                        .foregroundStyle(.auroraTextPrimary)
                }
                .tint(.accentColor)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uses holiday icons during the season, then restores your chosen icon.")
                        .foregroundStyle(.auroraTextQuaternary)
                    if viewModel.displayedIcon != viewModel.selection {
                        Text("Now showing \(viewModel.displayedIcon.rawValue.capitalized).")
                            .foregroundStyle(.auroraTextSecondary)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.auroraLive)
                    }
                }
                .auroraText(.caption)
            }
            .listRowBackground(Color.auroraSettingsRow)

            Section {
                ForEach(AppIconPreference.allCases, id: \.self) { icon in
                    Button {
                        Task { await viewModel.select(icon) }
                    } label: {
                        AppIconRow(icon: icon, isChosen: viewModel.selection == icon)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(Color.auroraSettingsRow)
            }
        }
        .disabled(viewModel.isUpdating)
        .animation(.default, value: viewModel.displayedIcon != viewModel.selection)
        .animation(.default, value: viewModel.errorMessage)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.auroraSettingsSheet)
        .navigationTitle("App Icon")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("App Icon").auroraText(.headline)
            }
        }
    }
}

/// Preview artwork ships in the app's asset catalog as `AppIconPreview-<preference>`, one
/// image per case — the app bundle supplies it, so the row renders nothing in a hostless test.
private struct AppIconRow: View {
    let icon: AppIconPreference
    let isChosen: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(decorative: "AppIconPreview-\(icon.rawValue)")
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(icon.rawValue.capitalized)
                .auroraText(.headline)
                .foregroundStyle(.auroraTextPrimary)
            Spacer()
            if isChosen {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
