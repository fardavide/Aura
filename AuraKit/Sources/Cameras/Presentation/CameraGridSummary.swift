import SwiftUI

import CamerasDomain
import CommonDesign

/// The group filter chips above the grid: "All" plus one per configured camera group. Selecting a
/// chip filters the tiles to that group; "All" clears the filter. Scrolls horizontally so a long
/// group list never wraps. `leadingPadding` matches the screen's own edge (`CameraSummaryChips`
/// takes the same input) so every row on the screen starts flush with the title and the wall.
struct GroupChips: View {
    let groups: [CameraGroup]
    let selected: String?
    let onSelect: (String?) -> Void
    let leadingPadding: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: selected == nil) { onSelect(nil) }
                ForEach(groups) { group in
                    chip(group.name, isSelected: selected == group.name) { onSelect(group.name) }
                }
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, 4)
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Text(label)
                    .auroraText(.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AuroraGradient.diagonal, in: Capsule())
            } else {
                Text(label)
                    .auroraText(.chip)
                    .foregroundStyle(.auroraTextPrimary)
                    .auroraChip()
            }
        }
        .buttonStyle(.plain)
    }
}

/// The chip row above the grid: up to four best-effort chips — the current activity (tap to jump to
/// that camera), today's event tally, recording-disk status, and how many visible cameras are
/// offline. Each chip is present only when its data loaded, so the row can never show a stale or
/// placeholder value; `CameraGridViewModel.hasSummaryChips` gates the row itself.
struct CameraSummaryChips: View {
    let rightNow: CameraGridViewModel.RightNow?
    let todayChipText: String?
    let todayBreakdownText: String?
    let freeBytes: Int64?
    let retentionChipText: String?
    let offlineChipText: String?
    let leadingPadding: CGFloat

    // Byte counts read the environment locale (not the process one) so they localize with the app
    // and render deterministically under the pinned snapshot locale.
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let rightNow {
                    activityChip(rightNow)
                }
                if let todayChipText {
                    plainChip(todayText(todayChipText), tint: .auroraTextPrimary)
                }
                if let freeBytes {
                    plainChip(storageText(freeBytes), tint: .auroraTextPrimary)
                }
                if let offlineChipText {
                    plainChip(offlineChipText, tint: .auroraTextSecondary)
                }
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, 4)
        }
    }

    private func activityChip(_ rightNow: CameraGridViewModel.RightNow) -> some View {
        NavigationLink(value: rightNow.camera) {
            HStack(spacing: 6) {
                Circle().frame(width: 6, height: 6)
                Text(rightNow.label)
                Text("· \(rightNow.camera.friendlyName ?? rightNow.camera.name.value)").opacity(0.75)
            }
            .auroraBadge(tone(for: rightNow.severity), size: .regular)
        }
        .buttonStyle(.plain)
        .lineLimit(1)
    }

    private func plainChip(_ text: String, tint: Color) -> some View {
        Text(text).auroraText(.chip).foregroundStyle(tint).auroraChip()
    }

    private func tone(for severity: CameraActivity.Severity) -> AuroraBadgeTone {
        switch severity {
        case .alert: .alert
        case .detection: .detection
        }
    }

    private func todayText(_ text: String) -> String {
        guard horizontalSizeClass != .compact, let todayBreakdownText else { return text }
        return "\(text) · \(todayBreakdownText)"
    }

    private func storageText(_ freeBytes: Int64) -> String {
        let base = "\(freeBytes.formatted(.byteCount(style: .file).locale(locale))) free"
        guard horizontalSizeClass != .compact, let retentionChipText else { return base }
        return "\(base) · \(retentionChipText)"
    }
}
