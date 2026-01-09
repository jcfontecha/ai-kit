import Foundation

#if canImport(XCTest)
import CoreGraphics
import ImageIO
import XCTest

public enum SnapshotTesting {
  public static func assertSnapshot<Value: Encodable>(
    _ value: Value,
    named name: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) {
    do {
      let snapshotPath = try resolveSnapshotPath(
        filePath: "\(file)",
        testName: testName,
        named: name,
        fileExtension: "json"
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(value)
      let current = String(decoding: data, as: UTF8.self) + "\n"

      let record = shouldRecordSnapshots(snapshotPath: snapshotPath)

      if record {
        try FileManager.default.createDirectory(
          at: snapshotPath.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try current.write(to: snapshotPath, atomically: true, encoding: .utf8)
        return
      }

      guard FileManager.default.fileExists(atPath: snapshotPath.path) else {
        XCTFail(
          "Missing snapshot at \(snapshotPath.path). Re-run with AIKIT_SNAPSHOT_RECORD=1 to record.",
          file: file,
          line: line
        )
        return
      }

      let expected = try String(contentsOf: snapshotPath, encoding: .utf8)
      XCTAssertEqual(current, expected, file: file, line: line)
    } catch {
      XCTFail("Snapshot error: \(error)", file: file, line: line)
    }
  }

  public static func assertSnapshotPNG(
    _ pngData: Data,
    named name: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) {
    do {
      let snapshotPath = try resolveSnapshotPath(
        filePath: "\(file)",
        testName: testName,
        named: name,
        fileExtension: "png"
      )

      let record = shouldRecordSnapshots(snapshotPath: snapshotPath)
      if record {
        try FileManager.default.createDirectory(
          at: snapshotPath.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try pngData.write(to: snapshotPath, options: [.atomic])
        return
      }

      guard FileManager.default.fileExists(atPath: snapshotPath.path) else {
        XCTFail(
          "Missing snapshot at \(snapshotPath.path). Re-run with AIKIT_SNAPSHOT_RECORD=1 to record.",
          file: file,
          line: line
        )
        return
      }

      let expected = try Data(contentsOf: snapshotPath)

      // Fast path.
      if pngData == expected {
        return
      }

      // PNG bytes can differ (metadata / compression) across environments even when pixels match.
      if try pngPixelsApproximatelyEqual(pngData, expected) {
        return
      }

      XCTAssertEqual(pngData, expected, file: file, line: line)
    } catch {
      XCTFail("Snapshot error: \(error)", file: file, line: line)
    }
  }

  private static func assertSnapshotData(
    _ data: Data,
    named name: String?,
    file: StaticString,
    testName: String,
    fileExtension: String,
    line: UInt
  ) {
    do {
      let snapshotPath = try resolveSnapshotPath(
        filePath: "\(file)",
        testName: testName,
        named: name,
        fileExtension: fileExtension
      )

      let record = shouldRecordSnapshots(snapshotPath: snapshotPath)
      if record {
        try FileManager.default.createDirectory(
          at: snapshotPath.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try data.write(to: snapshotPath, options: [.atomic])
        return
      }

      guard FileManager.default.fileExists(atPath: snapshotPath.path) else {
        XCTFail(
          "Missing snapshot at \(snapshotPath.path). Re-run with AIKIT_SNAPSHOT_RECORD=1 to record.",
          file: file,
          line: line
        )
        return
      }

      let expected = try Data(contentsOf: snapshotPath)
      XCTAssertEqual(data, expected, file: file, line: line)
    } catch {
      XCTFail("Snapshot error: \(error)", file: file, line: line)
    }
  }

  private static func resolveSnapshotPath(
    filePath: String,
    testName: String,
    named: String?,
    fileExtension: String
  ) throws -> URL {
    let fileURL = URL(fileURLWithPath: filePath)
    let testFileBase = fileURL.deletingPathExtension().lastPathComponent

    let sanitizedTestName = sanitizeFilename(testName)
    let suffix = named.map { "-" + sanitizeFilename($0) } ?? ""
    let snapshotFile = sanitizedTestName + suffix + "." + fileExtension

    // Prefer repo-root-relative `Tests/__Snapshots__` (derived from `.../Tests/...`).
    if let testsIndex = fileURL.pathComponents.lastIndex(of: "Tests") {
      let rootComponents = Array(fileURL.pathComponents.prefix(upTo: testsIndex))
      let root = URL(
        fileURLWithPath: rootComponents.joined(separator: "/"),
        isDirectory: true
      )
      return root
        .appendingPathComponent("Tests", isDirectory: true)
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(testFileBase, isDirectory: true)
        .appendingPathComponent(snapshotFile, isDirectory: false)
    }

    // Fallback: alongside the test file.
    return fileURL
      .deletingLastPathComponent()
      .appendingPathComponent("__Snapshots__", isDirectory: true)
      .appendingPathComponent(testFileBase, isDirectory: true)
      .appendingPathComponent(snapshotFile, isDirectory: false)
  }

  private static func sanitizeFilename(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
    return s
      .replacingOccurrences(of: "()", with: "")
      .unicodeScalars
      .map { allowed.contains($0) ? Character($0) : "-" }
      .reduce(into: "") { $0.append($1) }
      .replacingOccurrences(of: "--", with: "-")
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func shouldRecordSnapshots(snapshotPath: URL) -> Bool {
    if ProcessInfo.processInfo.environment["AIKIT_SNAPSHOT_RECORD"] == "1" {
      return true
    }

    // Optional marker file for recording without env vars (useful in sandboxed runners).
    // Repo root is inferred from the resolved `.../Tests/__Snapshots__/...` path.
    let root = snapshotPath
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    return FileManager.default.fileExists(atPath: root.appendingPathComponent(".aikit_snapshot_record").path)
  }

  private static func pngPixelsApproximatelyEqual(_ a: Data, _ b: Data) throws -> Bool {
    let imageA = try decodePNG(a)
    let imageB = try decodePNG(b)

    guard imageA.width == imageB.width, imageA.height == imageB.height else {
      return false
    }

    let bytesA = try rgba8Bytes(imageA)
    let bytesB = try rgba8Bytes(imageB)

    // Antialiasing/text rasterization can vary slightly across OS/toolchain versions even when layout is
    // identical. Allow a tiny amount of per-channel drift to avoid flakey snapshots while still catching
    // real regressions.
    if bytesA == bytesB {
      return true
    }

    let width = imageA.width
    let height = imageA.height
    let totalPixels = width * height

    let maxPerChannelDelta: Int = 2
    let maxDifferentPixelFraction: Double = 0.001 // 0.1%
    let allowedDifferentPixels = max(0, Int(Double(totalPixels) * maxDifferentPixelFraction))

    var differentPixels = 0
    for i in stride(from: 0, to: min(bytesA.count, bytesB.count), by: 4) {
      let dr = abs(Int(bytesA[i + 0]) - Int(bytesB[i + 0]))
      let dg = abs(Int(bytesA[i + 1]) - Int(bytesB[i + 1]))
      let db = abs(Int(bytesA[i + 2]) - Int(bytesB[i + 2]))
      let da = abs(Int(bytesA[i + 3]) - Int(bytesB[i + 3]))

      if max(dr, dg, db, da) > maxPerChannelDelta {
        differentPixels += 1
        if differentPixels > allowedDifferentPixels {
          return false
        }
      }
    }

    return true
  }

  private static func decodePNG(_ data: Data) throws -> CGImage {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
          let image = CGImageSourceCreateImageAtIndex(source, 0, options)
    else {
      throw NSError(domain: "AIKitTestKit.SnapshotTesting", code: 1)
    }
    return image
  }

  private static func rgba8Bytes(_ image: CGImage) throws -> Data {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let byteCount = bytesPerRow * height

    var bytes = Data(count: byteCount)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
      .union(.byteOrder32Big)

    try bytes.withUnsafeMutableBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        throw NSError(domain: "AIKitTestKit.SnapshotTesting", code: 2)
      }
      guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
      ) else {
        throw NSError(domain: "AIKitTestKit.SnapshotTesting", code: 3)
      }

      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return bytes
  }
}
#else
public enum SnapshotTesting {}
#endif
