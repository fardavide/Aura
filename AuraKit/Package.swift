// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AuraKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(
            name: "AuraKit",
            targets: ["CamerasDomain", "CamerasData", "CommonNetwork", "CommonFrigate"]
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
    ],
    swiftLanguageModes: [.v6]
)
