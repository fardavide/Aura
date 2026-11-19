import Foundation
import Testing

import SettingsDomain
import TestDoubles

@MainActor
struct ChangeAppIconTests {
    @Test func `given an existing alternate icon when Christmas ends then the chosen icon is restored`() async throws {
        // given
        let repository = FakeSettingsRepository()
        let switcher = FakeAppIconSwitcher(current: .signal)
        let december7 = try #require(Calendar.iso8601Utc.date(from: DateComponents(year: 2026, month: 12, day: 7)))
        let january8 = try #require(Calendar.iso8601Utc.date(from: DateComponents(year: 2027, month: 1, day: 8)))

        // when
        try await ChangeAppIcon(repository: repository, switcher: switcher)
            .execute(.refresh, at: december7, in: .gmt)
        try await ChangeAppIcon(repository: repository, switcher: switcher)
            .execute(.refresh, at: january8, in: .gmt)

        // then
        #expect(switcher.appliedIcons == [.christmas, .signal])
    }

    @Test(arguments: [
        (2026, 12, 6, AppIconPreference.signal),
        (2026, 12, 7, .christmas),
        (2026, 12, 31, .christmas),
        (2027, 1, 1, .christmas),
        (2027, 1, 7, .christmas),
        (2027, 1, 8, .signal),
    ])
    func `when refreshing then the local Christmas dates include both boundary days`(
        year: Int, month: Int, day: Int, expected: AppIconPreference
    ) async throws {
        // given
        let switcher = FakeAppIconSwitcher(current: .signal)
        let date = try #require(Calendar.iso8601Utc.date(from: DateComponents(year: year, month: month, day: day)))
        let timeZone = try #require(TimeZone(secondsFromGMT: 3_600))

        // when
        try await ChangeAppIcon(repository: FakeSettingsRepository(), switcher: switcher)
            .execute(.refresh, at: date.addingTimeInterval(-1_800), in: timeZone)

        // then
        #expect(switcher.current() == expected)
    }

    @Test func `given seasonal icons are off when Christmas starts then the chosen icon stays in place`() async throws {
        // given
        let repository = FakeSettingsRepository()
        repository.saveAppIconSettings(AppIconSettings(selection: .signal, usesSeasonalIcons: false))
        let switcher = FakeAppIconSwitcher(current: .signal)
        let christmas = try #require(Calendar.iso8601Utc.date(from: DateComponents(year: 2026, month: 12, day: 25)))

        // when
        try await ChangeAppIcon(repository: repository, switcher: switcher)
            .execute(.refresh, at: christmas, in: .gmt)

        // then
        #expect(switcher.appliedIcons.isEmpty)
    }

    @Test func `when choosing Christmas outside the season then Christmas remains selected on refresh`() async throws {
        // given
        let repository = FakeSettingsRepository()
        let switcher = FakeAppIconSwitcher(current: .signal)
        let july = try #require(Calendar.iso8601Utc.date(from: DateComponents(year: 2027, month: 7, day: 1)))
        let change = ChangeAppIcon(repository: repository, switcher: switcher)
        try await change.execute(.select(.christmas), at: july, in: .gmt)

        // when
        try await change.execute(.refresh, at: july, in: .gmt)

        // then
        #expect(switcher.appliedIcons == [.christmas])
    }
}

private extension Calendar {
    static var iso8601Utc: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }
}
