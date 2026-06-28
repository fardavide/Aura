import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Builds a SwiftUI `Image` from raw bytes across iOS (UIKit) and macOS (AppKit).
public func platformImage(from data: Data) -> Image? {
    #if canImport(UIKit)
    UIImage(data: data).map(Image.init(uiImage:))
    #elseif canImport(AppKit)
    NSImage(data: data).map(Image.init(nsImage:))
    #else
    nil
    #endif
}
