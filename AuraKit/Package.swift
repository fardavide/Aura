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
                "CommonNetwork", "CommonFrigate", "CommonKeychain",
                "SettingsDomain", "SettingsData",
                "CamerasPresentation", "SettingsPresentation",
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
            dependencies: ["CamerasDomain"],
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
    ],
    swiftLanguageModes: [.v6]
)
