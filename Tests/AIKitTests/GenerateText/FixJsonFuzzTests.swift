import XCTest
import AIKitProviders
@testable @_spi(Advanced) import AIKit

/// Property-based fuzzer for the partial-JSON repair path (`OutputParsing.parsePartialJSONValue`).
///
/// The oracle is fully mechanical, so the compute goes here rather than into hand-authored cases:
/// generate many valid JSON documents, truncate each at every character prefix, and assert the
/// repair invariant that needs no expected values —
///
///   INVARIANT (prefix-monotonic recoverability): if `parsePartial` returns non-nil for some
///   prefix of a valid document D, it must stay non-nil for every longer prefix of D. A longer
///   prefix carries strictly more confirmed-valid input, so it can never become *less* parseable.
///   A nil-regression means the repair mishandled the extra character — a false-nil bug.
final class FixJsonFuzzTests: XCTestCase {

  /// Deterministic generator so any failure reproduces from the seed.
  struct LCG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
      z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
      return z ^ (z >> 31)
    }
  }

  // Strings deliberately include control chars (0x01, 0x1f) so JSONEncoder emits real \uXXXX
  // escapes, plus quote/backslash/newline/tab and multibyte glyphs — the fragile surfaces.
  private static let stringPalette: [Character] =
    ["a", "b", " ", "\"", "\\", "\n", "\t", "\u{01}", "\u{1f}", "/", "é", "中", "😀"]

  private func randomString(_ rng: inout LCG) -> String {
    let len = Int.random(in: 0...8, using: &rng)
    var s = ""
    for _ in 0..<len {
      s.append(Self.stringPalette[Int.random(in: 0..<Self.stringPalette.count, using: &rng)])
    }
    return s
  }

  private func randomScalar(_ rng: inout LCG) -> Any {
    switch Int.random(in: 0..<6, using: &rng) {
    case 0: return randomString(&rng)
    case 1: return Int.random(in: -1_000_000...1_000_000, using: &rng)
    case 2: return Double(Int.random(in: -100_000...100_000, using: &rng)) / 100.0   // decimals
    case 3: return Double(Int.random(in: 1...9, using: &rng)) * 1e8                    // exponent form
    case 4: return Bool.random(using: &rng)
    default: return NSNull()
    }
  }

  private func randomValue(_ rng: inout LCG, depth: Int) -> Any {
    if depth >= 3 || Int.random(in: 0..<100, using: &rng) < 40 {
      return randomScalar(&rng)
    }
    if Int.random(in: 0..<2, using: &rng) == 0 {
      var dict: [String: Any] = [:]
      for k in 0..<Int.random(in: 0...4, using: &rng) {
        dict["k\(k)_\(Int.random(in: 0...9, using: &rng))"] = randomValue(&rng, depth: depth + 1)
      }
      return dict
    }
    return (0..<Int.random(in: 0...4, using: &rng)).map { _ in randomValue(&rng, depth: depth + 1) }
  }

  private func canonicalJSON(_ value: Any) -> String? {
    guard let data = try? JSONSerialization.data(
      withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]
    ) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func testPrefixMonotonicRecoverability() {
    struct Witness { let doc: String; let cut: Int; let prefix: String }
    var witnesses: [Witness] = []
    var docsTested = 0
    var prefixEvals = 0

    var rng = LCG(seed: 0xA1F0_C0DE_1234_5678)

    for _ in 0..<2500 {
      let value = randomValue(&rng, depth: 0)
      guard let json = canonicalJSON(value) else { continue }
      let chars = Array(json)
      guard chars.count >= 2 else { continue }
      docsTested += 1

      var sawNonNil = false
      for cut in 1...chars.count {
        let prefix = String(chars.prefix(cut))
        let result = OutputParsing.parsePartialJSONValue(prefix)   // must never crash
        prefixEvals += 1
        if result != nil {
          sawNonNil = true
        } else if sawNonNil {
          witnesses.append(Witness(doc: json, cut: cut, prefix: prefix))
          break   // one witness per doc is enough to characterize
        }
      }
    }

    print("FUZZ\tdocs=\(docsTested)\tprefixEvals=\(prefixEvals)\twitnesses=\(witnesses.count)")
    for w in witnesses.prefix(40) {
      let cutChar = Array(w.doc)[w.cut - 1]
      print("FUZZ-WITNESS\tcut=\(w.cut)\tcutChar=\(String(reflecting: cutChar))\tprefix=\(String(reflecting: w.prefix))\tdoc=\(String(reflecting: w.doc))")
    }

    XCTAssertTrue(
      witnesses.isEmpty,
      "Prefix-monotonic recoverability violated in \(witnesses.count)/\(docsTested) docs — see FUZZ-WITNESS lines."
    )
  }
}
