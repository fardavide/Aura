import SwiftUI

import CommonDesign
import SettingsDomain

public struct AppIconView: View {
    @State private var viewModel: AppIconViewModel

    public init(viewModel: AppIconViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Form {
            Section {
                ForEach(AppIconPreference.allCases, id: \.self) { icon in
                    Button {
                        Task { await viewModel.select(icon) }
                    } label: {
                        AppIconRow(icon: icon, isChosen: viewModel.selection == icon)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.auroraSettingsRow)
            } footer: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).auroraText(.caption).foregroundStyle(.auroraLive)
                }
            }
        }
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
        .onAppear { viewModel.onAppear() }
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
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
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
