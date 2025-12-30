import Foundation

#if canImport(XCTest) && canImport(SwiftUI)
import XCTest
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public extension SnapshotTesting {
  @MainActor
  static func assertSnapshotImage<V: View>(
    _ view: V,
    size: CGSize,
    scale: CGFloat = 2,
    named name: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = .init(size)
    renderer.scale = scale

    guard let cgImage = renderer.cgImage else {
      XCTFail("Failed to render SwiftUI view snapshot.", file: file, line: line)
      return
    }

    do {
      let png = try pngData(from: cgImage)
      assertSnapshotPNG(png, named: name, file: file, testName: testName, line: line)
    } catch {
      XCTFail("Snapshot error: \(error)", file: file, line: line)
    }
  }

  private static func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else {
      throw SnapshotImageError.unableToCreateDestination
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw SnapshotImageError.unableToFinalizeDestination
    }

    return data as Data
  }

  private enum SnapshotImageError: Error {
    case unableToCreateDestination
    case unableToFinalizeDestination
  }
}
#endif

