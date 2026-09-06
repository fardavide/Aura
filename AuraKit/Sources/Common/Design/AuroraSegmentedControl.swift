import SwiftUI

/// Which glass surface hosts the control. `.well` (a recessed track box, no nested `glassEffect`)
/// is for a control sitting on chrome that already carries its own glass (the Settings theme
/// picker inside `auroraSettingsSheet()` — one glass layer per surface).
public enum AuroraSegmentedContainer: Sendable {
    case glass
    case well
}

/// Which gradient fills the selected segment. `.badge` (violet→pink) is the default; `.diagonal`
/// (the full three-stop brand gradient) is for a control that is itself the primary action on its
/// screen (the Timeline-detail zoom picker).
public enum AuroraSegmentedFill: Sendable {
    case badge
    case diagonal

    var gradient: LinearGradient {
        switch self {
        case .badge: AuroraGradient.badge
        case .diagonal: AuroraGradient.diagonal
        }
    }
}

public struct AuroraSegmentedControl<Option: Hashable & Sendable>: View {
    @Environment(\.designMotion) private var motion
    private let options: [Option]
    @Binding private var selection: Option
    private let title: (Option) -> String
    private let container: AuroraSegmentedContainer
    private let selectedFill: AuroraSegmentedFill

    public init(
        options: [Option],
        selection: Binding<Option>,
        container: AuroraSegmentedContainer = .glass,
        selectedFill: AuroraSegmentedFill = .badge,
        title: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.container = container
        self.selectedFill = selectedFill
        self.title = title
    }

    public var body: some View {
        Group {
            switch container {
            case .glass:
                segments
                    .glassEffect(.regular.tint(.auroraChipFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.auroraChipBorder, lineWidth: 1) }
            case .well:
                segments
                    .auroraTrackWell(cornerRadius: 11)
            }
        }
        .animation(motion == .animated ? .snappy(duration: 0.2) : nil, value: selection)
        .accessibilityElement(children: .contain)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .auroraText(.chip)
                        .foregroundStyle(option == selection ? .white : .auroraTextSecondary)
                        .frame(minWidth: 34)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background {
                            if option == selection {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selectedFill.gradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? [.isSelected] : [])
            }
        }
        .padding(3)
    }
}
