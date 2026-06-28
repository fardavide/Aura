import SwiftUI

import TimelineDomain

/// Selects which day the timeline shows (capped at today).
struct DayPickerView: View {
    let day: TimeRange
    let onSelectDay: (Date) -> Void

    @State private var selected: Date

    init(day: TimeRange, onSelectDay: @escaping (Date) -> Void) {
        self.day = day
        self.onSelectDay = onSelectDay
        _selected = State(initialValue: day.start)
    }

    var body: some View {
        DatePicker("Day", selection: $selected, in: ...Date(), displayedComponents: .date)
            .labelsHidden()
            .onChange(of: selected) { _, date in onSelectDay(date) }
    }
}
