import SwiftUI

/// The toolbar every tab shares: a left-aligned title (+ optional subtitle), the tab's own
/// accessories, and the Settings gear, always last — one inset, one gear, so the four tabs can't
/// drift apart. Pinned above a screen's scrolling content, with a glass surface that fades in once
/// content has scrolled behind it — the same "content scrolls behind glass" read a system
/// navigation bar gives for free, without losing the left-aligned, Aurora-styled title a system
/// toolbar cannot render (a `.principal` toolbar item centres its content; `.topBarLeading`
/// collapses anything wider than an icon into an overflow menu — verified empirically, neither
/// renders this design). Pair with `.auroraTrackingScrollGlass` on the sibling `ScrollView`.
public struct AuroraTabHeader<Subtitle: View, Accessory: View>: View {
    private let title: String
    private let isGlass: Bool
    private let onOpenSettings: () -> Void
    private let subtitle: Subtitle
    private let accessory: Accessory

    public init(
        _ title: String,
        isGlass: Bool,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder subtitle: () -> Subtitle = { EmptyView() },
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.isGlass = isGlass
        self.onOpenSettings = onOpenSettings
        self.subtitle = subtitle()
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .auroraText(.screenTitle)
                    .foregroundStyle(.auroraTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                subtitle
                    .auroraText(.captionEmphasis)
                    .foregroundStyle(.auroraTextSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                accessory
                AuroraSettingsButton(action: onOpenSettings)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background {
            if isGlass {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.auroraSheetTint), in: Rectangle())
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isGlass)
    }
}

/// The one Settings gear. Lives in `AuroraTabHeader`, and anywhere a layout hides that header but
/// still owes the user a route to Settings.
public struct AuroraSettingsButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .foregroundStyle(.auroraTextPrimary)
                .auroraChip()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

extension View {
    /// Reports whether the scroll view has moved past its top edge, for a sibling
    /// `AuroraTabHeader`'s `isGlass`. `threshold` absorbs the small negative offsets a bounce
    /// or a rubber-band overscroll produces at rest, so the glass doesn't flicker on a tiny nudge.
    public func auroraTrackingScrollGlass(isGlass: Binding<Bool>, threshold: CGFloat = 8) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > threshold
        } action: { _, isPast in
            isGlass.wrappedValue = isPast
        }
    }
}
