import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct AppIconViewModelTests {

    @Test func `given a chosen icon when appearing then it is prefilled`() {
        // given
        let scenario = Scenario(current: .signal)

        // when
        scenario.sut.onAppear()

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
        scenario.sut.onAppear()

        // when
        await scenario.sut.select(.thin)

        // then
        #expect(scenario.sut.selection == .halo)
        #expect(scenario.sut.errorMessage != nil)
    }

    @Test func `given an icon is already showing when selecting it again then nothing is applied`() async {
        // given
        let scenario = Scenario(current: .heavy)
        scenario.sut.onAppear()

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
}

@MainActor
private struct Scenario {
    let switcher: FakeAppIconSwitcher
    let sut: AppIconViewModel

    init(
        current: AppIconPreference = .halo,
        applyResult: Result<Void, SettingsError> = .success(())
    ) {
        switcher = FakeAppIconSwitcher(current: current, applyResult: applyResult)
        sut = AppIconViewModel(
            loadAppIcon: LoadAppIcon(switcher: switcher),
            changeAppIcon: ChangeAppIcon(switcher: switcher)
        )
    }
}
