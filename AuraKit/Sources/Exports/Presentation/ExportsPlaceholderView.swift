import SwiftUI

import CommonDesign

/// The centred group both content-free states use — empty and unreachable. Both teach something,
/// so both carry a message, and every button here does something the user can perceive.
struct ExportsPlaceholderView: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let symbol: String
    let symbolTint: Color
    let title: String
    let message: String
    /// Nil where the state genuinely has no next step to offer — the detail side before a clip is
    /// picked. Inventing a button there would send the user away from the thing they are choosing.
    let primary: Action?
    let secondary: Action?
    /// Non-nil while the primary action is running: its label, and the reason printed beneath —
    /// so the disabled control always says why it is disabled.
    let busy: (title: String, reason: String)?

    var body: some View {
        VStack(spacing: 18) {
            icon
            VStack(spacing: 8) {
                Text(title)
                    .auroraText(.heroTitle)
                    .foregroundStyle(.auroraTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .auroraText(.body)
                    .foregroundStyle(.auroraTextSecondary)
            }
            .multilineTextAlignment(.center)
            buttons
        }
        .padding(.horizontal, 34)
        // Lifts the group optically above the tab bar rather than centring it in the raw frame.
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.auroraSheetTint)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.auroraSheetBorder, lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(symbolTint)
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 8) {
            if let primary {
                Button(action: primary.perform) {
                    HStack(spacing: 8) {
                        if busy != nil {
                            ProgressView().controlSize(.small)
                        }
                        Text(busy?.title ?? primary.title)
                    }
                }
                .buttonStyle(.auroraGradient(glow: true))
                .disabled(busy != nil)
                .opacity(busy == nil ? 1 : 0.55)
            }

            if let busy {
                Text(busy.reason)
                    .auroraText(.caption)
                    .foregroundStyle(.auroraTextSecondary)
                    .multilineTextAlignment(.center)
            }
            if let secondary {
                // Stays live throughout a retry: the user may need to fix the address mid-attempt,
                // and a screen where every control is disabled is a dead end.
                Button(secondary.title, action: secondary.perform)
                    .buttonStyle(ExportChipButtonStyle())
            }
        }
    }
}
