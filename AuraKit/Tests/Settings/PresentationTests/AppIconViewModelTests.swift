import Foundation
import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct AppIconViewModelTests {

    @Test func `given a chosen icon when opening the picker then it is prefilled`() {
        // given - when
        let scenario = Scenario(current: .signal)

        // then
        #expect(scenario.sut.selection == .signal)
    }

    @Test func `when selecting an icon then it is applied and becomes the selection`() async {
        // given
        let scenario = Scenario()

        // when
        await scenario.sut.select(.aurora)

        // then
        #expect(scenario.switcher.appliedIcons == [.aurora])
        #expect(scenario.sut.selection == .aurora)
        #expect(scenario.sut.errorMessage == nil)
    }

    @Test func `given the system rejects the change when selecting then the selection reverts and an error shows`() async {
        // given
        let scenario = Scenario(current: .halo, applyResult: .failure(.iconChangeFailed))

        // when
        await scenario.sut.select(.thin)

        // then
        #expect(scenario.sut.selection == .halo)
        #expect(scenario.sut.errorMessage != nil)
    }

    @Test func `given an icon is already showing when selecting it again then nothing is applied`() async {
        // given
        let scenario = Scenario(current: .heavy)

        // when
        await scenario.sut.select(.heavy)

        // then
        #expect(scenario.switcher.appliedIcons.isEmpty)
    }

    @Test func `given an earlier failure when the next change succeeds then the error is cleared`() async {
        // given
        let scenario = Scenario(applyResult: .failure(.iconChangeFailed))
        await scenario.sut.select(.sweep)
        scenario.switcher.applyResult = .success(())

        // when
        await scenario.sut.select(.daylight)

        // then
        #expect(scenario.sut.errorMessage == nil)
        #expect(scenario.sut.selection == .daylight)
    }

    @Test func `given a seasonal icon is showing when choosing another icon then turning off seasonal icons restores the new choice`() async throws {
        // given
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let christmas = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 25)))
        let scenario = Scenario(current: .signal, now: christmas)
        await scenario.sut.refresh()
        #expect(scenario.sut.usesSeasonalIcons)
        #expect(scenario.sut.displayedIcon == .christmas)

        // when
        await scenario.sut.select(.aurora)
        #expect(scenario.sut.displayedIcon == .christmas)
        await scenario.sut.setSeasonalIcons(false)

        // then
        #expect(scenario.sut.displayedIcon == .aurora)
        #expect(!scenario.sut.usesSeasonalIcons)
        #expect(scenario.switcher.appliedIcons == [.christmas, .aurora])
    }
}

@MainActor
private struct Scenario {
    let switcher: FakeAppIconSwitcher
    let sut: AppIconViewModel

    init(
        current: AppIconPreference = .halo,
        applyResult: Result<Void, SettingsError> = .success(()),
        now: Date = Date(timeIntervalSince1970: 14 * 86_400)
    ) {
        switcher = FakeAppIconSwitcher(current: current, applyResult: applyResult)
        let repository = FakeSettingsRepository()
        sut = AppIconViewModel(
            loadAppIcon: LoadAppIcon(repository: repository, switcher: switcher),
            changeAppIcon: ChangeAppIcon(repository: repository, switcher: switcher),
            now: { now },
            timeZone: { .gmt }
        )
    }
}
