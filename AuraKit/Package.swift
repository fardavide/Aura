// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AuraKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(
            name: "AuraKit",
            targets: [
                "CamerasDomain", "CamerasData",
                "CommonNetwork", "CommonFrigate", "CommonKeychain", "CommonPlayer",
                "SettingsDomain", "SettingsData",
                "CamerasPresentation", "SettingsPresentation",
                "EventsDomain", "EventsData", "EventsPresentation",
                "TimelineDomain", "TimelineData", "TimelinePresentation",
            ]
        ),
    ],
    targets: [
        .target(name: "CamerasDomain", path: "Sources/Cameras/Domain"),
        .testTarget(
            name: "CamerasDomainTests",
            dependencies: ["CamerasDomain"],
            path: "Tests/Cameras/DomainTests"
        ),

        .target(name: "CommonNetwork", path: "Sources/Common/Network"),
        .testTarget(
            name: "CommonNetworkTests",
            dependencies: ["CommonNetwork"],
            path: "Tests/Common/NetworkTests"
        ),

        .target(name: "CommonFrigate", path: "Sources/Common/Frigate"),
        .testTarget(
            name: "CommonFrigateTests",
            dependencies: ["CommonFrigate"],
            path: "Tests/Common/FrigateTests"
        ),

        .target(
            name: "CamerasData",
            dependencies: ["CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Sources/Cameras/Data"
        ),
        .testTarget(
            name: "CamerasDataTests",
            dependencies: ["CamerasData", "CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Tests/Cameras/DataTests"
        ),

        .target(name: "SettingsDomain", path: "Sources/Settings/Domain"),
        .testTarget(
            name: "SettingsDomainTests",
            dependencies: ["SettingsDomain"],
            path: "Tests/Settings/DomainTests"
        ),

        .target(name: "CommonKeychain", path: "Sources/Common/Keychain"),

        .target(name: "CommonPlayer", path: "Sources/Common/Player"),
        .testTarget(
            name: "CommonPlayerTests",
            dependencies: ["CommonPlayer"],
            path: "Tests/Common/PlayerTests"
        ),

        .target(
            name: "SettingsData",
            dependencies: ["SettingsDomain", "CommonKeychain"],
            path: "Sources/Settings/Data"
        ),
        .testTarget(
            name: "SettingsDataTests",
            dependencies: ["SettingsData", "SettingsDomain", "CommonKeychain"],
            path: "Tests/Settings/DataTests"
        ),

        .target(
            name: "CamerasPresentation",
            dependencies: ["CamerasDomain", "CommonPlayer"],
            path: "Sources/Cameras/Presentation"
        ),
        .testTarget(
            name: "CamerasPresentationTests",
            dependencies: ["CamerasPresentation", "CamerasDomain"],
            path: "Tests/Cameras/PresentationTests"
        ),

        .target(
            name: "SettingsPresentation",
            dependencies: ["SettingsDomain"],
            path: "Sources/Settings/Presentation"
        ),
        .testTarget(
            name: "SettingsPresentationTests",
            dependencies: ["SettingsPresentation", "SettingsDomain"],
            path: "Tests/Settings/PresentationTests"
        ),

        .target(
            name: "EventsDomain",
            dependencies: ["CamerasDomain"],
            path: "Sources/Events/Domain"
        ),
        .testTarget(
            name: "EventsDomainTests",
            dependencies: ["EventsDomain", "CamerasDomain"],
            path: "Tests/Events/DomainTests"
        ),

        .target(
            name: "EventsData",
            dependencies: ["EventsDomain", "CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Sources/Events/Data"
        ),
        .testTarget(
            name: "EventsDataTests",
            dependencies: ["EventsData", "EventsDomain", "CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Tests/Events/DataTests"
        ),

        .target(
            name: "EventsPresentation",
            dependencies: ["EventsDomain", "CamerasDomain", "CommonPlayer"],
            path: "Sources/Events/Presentation"
        ),
        .testTarget(
            name: "EventsPresentationTests",
            dependencies: ["EventsPresentation", "EventsDomain", "CamerasDomain"],
            path: "Tests/Events/PresentationTests"
        ),

        .target(
            name: "TimelineDomain",
            dependencies: ["CamerasDomain"],
            path: "Sources/Timeline/Domain"
        ),
        .testTarget(
            name: "TimelineDomainTests",
            dependencies: ["TimelineDomain", "CamerasDomain"],
            path: "Tests/Timeline/DomainTests"
        ),

        .target(
            name: "TimelineData",
            dependencies: ["TimelineDomain", "CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Sources/Timeline/Data"
        ),
        .testTarget(
            name: "TimelineDataTests",
            dependencies: ["TimelineData", "TimelineDomain", "CamerasDomain", "CommonFrigate", "CommonNetwork"],
            path: "Tests/Timeline/DataTests"
        ),

        .target(
            name: "TimelinePresentation",
            dependencies: ["TimelineDomain", "CamerasDomain", "CommonPlayer"],
            path: "Sources/Timeline/Presentation"
        ),
        .testTarget(
            name: "TimelinePresentationTests",
            dependencies: ["TimelinePresentation", "TimelineDomain", "CamerasDomain"],
            path: "Tests/Timeline/PresentationTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
