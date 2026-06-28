import Foundation

/// One element of `/api/preview/{camera}/start/{s}/end/{e}` (past-hour preview clip list).
struct PreviewClipDto: Decodable {
    let camera: String
    let src: String
    let type: String
    let start: Double
    let end: Double
}
