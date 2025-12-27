#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

import SwiftUI

extension Color {
  static var platformBackground: Color {
    #if os(iOS) || os(tvOS) || os(visionOS)
    Color(uiColor: .systemBackground)
    #elseif os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color.black
    #endif
  }
}

