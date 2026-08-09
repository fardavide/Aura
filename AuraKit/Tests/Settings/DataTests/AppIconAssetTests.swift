import Testing

import SettingsDomain
@testable import SettingsData

struct AppIconAssetTests {

    @Test func `given the icon the app ships with then it has no alternate asset name`() {
        #expect(AppIconAsset.name(for: .halo) == nil)
    }

    @Test func `then every alternate icon has an asset name of its own`() {
        // given
        let alternates = AppIconPreference.allCases.filter { $0 != .halo }

        // when
        let names = alternates.compactMap(AppIconAsset.name(for:))

        // then
        #expect(names.count == alternates.count)
        #expect(Set(names).count == alternates.count)
    }

    @Test func `given an asset name when looking it up then the icon round-trips`() throws {
        // given
        let name = try #require(AppIconAsset.name(for: .signal))

        // when - then
        #expect(AppIconAsset.icon(named: name) == .signal)
    }

    @Test func `given a name no longer in the catalog when looking it up then the shipped icon is assumed`() {
        #expect(AppIconAsset.icon(named: "AppIcon-Retired") == .halo)
    }
}
