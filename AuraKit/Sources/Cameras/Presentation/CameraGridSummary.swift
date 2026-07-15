import SwiftUI

import CamerasDomain

/// The group filter chips above the grid: "All" plus one per configured camera group. Selecting a
/// chip filters the tiles to that group; "All" clears the filter. Scrolls horizontally so a long
/// group list never wraps.
struct GroupChips: View {
    let groups: [CameraGroup]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: selected == nil) { onSelect(nil) }
                ForEach(groups) { group in
                    chip(group.name, isSelected: selected == group.name) { onSelect(group.name) }
                }
            }
            .padding(.leading)
            .padding(.trailing, 4)
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.thinMaterial),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

/// The summary card above the grid: three columns — what's happening RIGHT NOW (tap to jump to that
/// camera), TODAY's event tally, and RECORDING disk status. Each column degrades to a dash when its
/// best-effort data didn't load, so the card is always safe to show once the grid is loaded.
struct SummaryCard: View {
    let rightNow: CameraGridViewModel.RightNow?
    let todayEvents: EventCount?
    let storage: RecordingStorage?

    // Byte counts read the environment locale (not the process one) so they localize with the app
    // and render deterministically under the pinned snapshot locale.
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            rightNowColumn
            divider
            todayColumn
            divider
            recordingColumn
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 0.5))
        .padding(.horizontal)
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(width: 1).padding(.vertical, 10)
    }

    @ViewBuilder private var rightNowColumn: some View {
        if let rightNow {
            NavigationLink(value: rightNow.camera) {
                SummaryColumn(caption: "Right now") {
                    Label {
                        Text(rightNow.label).lineLimit(1)
                    } icon: {
                        Circle().fill(color(for: rightNow.severity)).frame(width: 7, height: 7)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color(for: rightNow.severity))
                } subtitle: {
                    Text(rightNow.camera.friendlyName ?? rightNow.camera.name.value)
                }
            }
            .buttonStyle(.plain)
        } else {
            SummaryColumn(caption: "Right now") {
                Label {
                    Text("All quiet")
                } icon: {
                    Circle().fill(.green).frame(width: 7, height: 7)
                }
                .font(.subheadline.weight(.bold))
            } subtitle: {
                Text("No activity")
            }
        }
    }

    private var todayColumn: some View {
        SummaryColumn(caption: "Today") {
            Text(todayEvents.map { "\($0.total) event\($0.total == 1 ? "" : "s")" } ?? "—")
                .font(.subheadline.weight(.bold))
        } subtitle: {
            Text(todayEvents.map(breakdownText) ?? " ")
        }
    }

    private var recordingColumn: some View {
        SummaryColumn(caption: "Recording") {
            Text(storage.map { "\($0.freeBytes.formatted(.byteCount(style: .file).locale(locale))) free" } ?? "—")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        } subtitle: {
            Text(retentionText ?? " ")
        }
    }

    private func color(for severity: CameraActivity.Severity) -> Color {
        switch severity {
        case .alert: .red
        case .detection: .orange
        }
    }

    private func breakdownText(_ events: EventCount) -> String {
        events.breakdown.prefix(2).map { "\($0.count) \($0.label)" }.joined(separator: " · ")
    }

    private var retentionText: String? {
        guard let days = storage?.retentionDays else { return nil }
        return "\(days) day\(days == 1 ? "" : "s") kept"
    }
}

/// One column of the summary card: a small uppercase caption over a bold value and a muted subtitle.
private struct SummaryColumn<Value: View, Subtitle: View>: View {
    let caption: String
    @ViewBuilder let value: Value
    @ViewBuilder let subtitle: Subtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.caption2.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            value
            subtitle
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
    }
}
