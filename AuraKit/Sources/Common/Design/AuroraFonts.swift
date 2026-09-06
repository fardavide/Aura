import CoreText
import SwiftUI

public enum AuroraFonts {
    /// PostScript names of the bundled static faces (verified with CoreText, see evidence).
    public enum Urbanist: String, CaseIterable, Sendable {
        case regular = "Urbanist-Regular"
        case medium = "Urbanist-Medium"
        case semiBold = "Urbanist-SemiBold"
        case bold = "Urbanist-Bold"
        case extraBold = "Urbanist-ExtraBold"
        case black = "Urbanist-Black"

        var systemWeight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semiBold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            case .black: .black
            }
        }
    }

    /// Process-scope registration of all six files, exactly once per process. `true` when every
    /// face is available afterwards (freshly registered or already registered — e.g. the
    /// app-hosted test bundle and the app both touching it). Thread-safe by `static let` semantics;
    /// `CTFontManagerRegisterFontURLs` completes synchronously (evidence probe), so the first
    /// `Font.custom` after reading this property already resolves.
    public static let isRegistered: Bool = {
        let urls = Urbanist.allCases.map { face in
            Bundle.module.url(forResource: face.rawValue, withExtension: "ttf")
        }
        guard urls.allSatisfy({ $0 != nil }) else {
            assertionFailure("CommonDesign bundle is missing an Urbanist face")
            return false
        }
        // `alreadyRegistered` (code 105) is expected when the app and the test host both touch
        // this; any other error surfaces below as an unresolvable face. Returning `true` keeps
        // registering the remaining files.
        CTFontManagerRegisterFontURLs(urls.compactMap { $0 } as CFArray, .process, true) { _, _ in true }
        let unresolved = Urbanist.allCases.filter { face in
            CTFontCopyPostScriptName(CTFontCreateWithName(face.rawValue as CFString, 12, nil)) as String != face.rawValue
        }
        guard unresolved.isEmpty else {
            assertionFailure("Urbanist faces not resolvable after registration: \(unresolved)")
            return false
        }
        return true
    }()

    /// The one place `Font.custom` is spelled. Falls back to the system font (same size, nearest
    /// weight) if registration failed, so a broken bundle degrades instead of rendering blank.
    public static func font(_ face: Urbanist, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        guard isRegistered else {
            return .system(size: size, weight: face.systemWeight)
        }
        return .custom(face.rawValue, size: size, relativeTo: textStyle)
    }
}
