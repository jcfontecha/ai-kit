import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Color {
  static var platformBackground: Color {
    #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color(white: 1.0)
    #endif
  }
}
