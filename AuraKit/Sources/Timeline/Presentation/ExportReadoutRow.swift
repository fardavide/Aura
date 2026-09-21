import Foundation
import SwiftUI

import CommonDesign

/// The exact clip, in words: where it starts, where it ends, how long it is.
///
/// The numerals are the system face with `tnum`, not Urbanist — matching every other number on
/// this panel, and the reason a second ticking past does not shuffle the row. Seconds are always
/// shown, because seconds are the resolution the export actually has.
struct ExportReadoutRow: View {
    let state: ExportEditorState
    /// The rail cannot hold `14:29:42 → 14:31:12` at 17 pt across 144 points, so it stacks the
    /// duration over the pair at a smaller size instead of truncating a time.
    let isNarrow: Bool
    let onResetToPlayhead: () -> Void

    var body: some View {
        if isNarrow { narrow } else { wide }
    }

    private var wide: some View {
        HStack(spacing: 9) {
            boundary("In", state.selection.start)
            Image(systemName: "arrow.right")
                .auroraText(.caption)
                .foregroundStyle(.auroraTextQuaternary)
            boundary("Out", state.selection.end)
            Spacer(minLength: 8)
            if state.showsResetToPlayhead { resetButton }
            durationCapsule
        }
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }

    private var narrow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                durationCapsule
                Spacer(minLength: 0)
                if state.showsResetToPlayhead { resetButton }
            }
            Text("\(timeText(state.selection.start)) → \(timeText(state.selection.end))")
                .auroraNumerals(.rulerLabel)
                .foregroundStyle(.auroraTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func boundary(_ label: String, _ instant: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .auroraText(.overline)
                .textCase(.uppercase)
                .foregroundStyle(.auroraTextQuaternary)
            Text(timeText(instant))
                .auroraNumerals(.exportBoundary)
                .foregroundStyle(.auroraTextPrimary)
                .contentTransition(.numericText())
        }
    }

    /// The number the user is steering, so it gets the recess and the emphasis.
    private var durationCapsule: some View {
        Text(ExportEditorState.clockText(state.selection.duration))
            .auroraNumerals(.exportDuration)
            .foregroundStyle(.auroraTextPrimary)
            .contentTransition(.numericText())
            .padding(.horizontal, 12)
            .frame(height: 30)
            .auroraTrackWell(cornerRadius: 10)
    }

    /// Absent until scrubbing takes the playhead out of the clip — see `showsResetToPlayhead`.
    private var resetButton: some View {
        Button(action: onResetToPlayhead) {
            Image(systemName: "arrow.counterclockwise")
                .imageScale(.small)
                .foregroundStyle(.auroraTextPrimary)
                .frame(width: 30, height: 30)
                .background(.auroraChipFill, in: Circle())
                .overlay { Circle().strokeBorder(.auroraChipBorder, lineWidth: 1) }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset to playhead")
    }

    private func timeText(_ instant: Date) -> String {
        instant.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
}
