import Foundation

enum SeasonalAppIcon {
    static func active(at date: Date, in timeZone: TimeZone) -> AppIconPreference? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return switch (month, day) {
        case (12, _), (1, 1...7): .christmas
        default: nil
        }
    }
}
