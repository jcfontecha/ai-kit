import Foundation

#if canImport(XCTest)
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

      let record = ProcessInfo.processInfo.environment["AIKIT_SNAPSHOT_RECORD"] == "1"

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
    assertSnapshotData(
      pngData,
      named: name,
      file: file,
      testName: testName,
      fileExtension: "png",
      line: line
    )
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

      let record = ProcessInfo.processInfo.environment["AIKIT_SNAPSHOT_RECORD"] == "1"
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
}
#else
public enum SnapshotTesting {}
#endif
