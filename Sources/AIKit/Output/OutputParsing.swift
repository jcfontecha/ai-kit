import Foundation
import AIKitProviders

enum OutputParsing {
  enum ParseFailure: Error {
    case parseFailed
    case schemaMismatch

    var message: String {
      switch self {
      case .parseFailed:
        return "No object generated: could not parse the response."
      case .schemaMismatch:
        return "No object generated: response did not match schema."
      }
    }
  }

  static func parseJSONValue(_ text: String) throws -> JSONValue {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
      throw ParseFailure.parseFailed
    }
    do {
      let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      if let value = JSONValue.from(object) {
        return value
      }
    } catch {
      throw ParseFailure.parseFailed
    }
    throw ParseFailure.parseFailed
  }

  static func parsePartialJSONValue(_ text: String) -> JSONValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let value = try? parseJSONValue(trimmed) { return value }
    guard let repaired = repairJSON(trimmed) else { return nil }
    return try? parseJSONValue(repaired)
  }

  static func decodeJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
  }

  static func encodeJSONValue(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func parsePartialElements<Element: Decodable>(
    text: String,
    elementType: Element.Type
  ) -> [Element]? {
    guard let arrayRange = findJSONArray(forKey: "elements", in: text) else { return nil }
    let arrayText = String(text[arrayRange])
    if isEmptyJSONArray(arrayText) { return [] }
    let elements = extractJSONArrayElements(from: arrayText)
    if elements.isEmpty { return nil }
    var decoded: [Element] = []
    for value in elements {
      if let element = try? decodeJSONValue(value, as: Element.self) {
        decoded.append(element)
      }
    }
    return decoded
  }

  static func parsePartialChoice(text: String, key: String) -> String? {
    guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
    var idx = keyRange.upperBound
    while idx < text.endIndex && text[idx].isWhitespace {
      idx = text.index(after: idx)
    }
    guard idx < text.endIndex, text[idx] == ":" else { return nil }
    idx = text.index(after: idx)
    while idx < text.endIndex && text[idx].isWhitespace {
      idx = text.index(after: idx)
    }
    guard idx < text.endIndex, text[idx] == "\"" else { return nil }
    idx = text.index(after: idx)
    var result = ""
    var escape = false
    while idx < text.endIndex {
      let ch = text[idx]
      if escape {
        result.append(ch)
        escape = false
      } else if ch == "\\" {
        escape = true
      } else if ch == "\"" {
        return result
      } else {
        result.append(ch)
      }
      idx = text.index(after: idx)
    }
    return result.isEmpty ? nil : result
  }

  private static func findJSONArray(forKey key: String, in text: String) -> Range<String.Index>? {
    guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
    var idx = keyRange.upperBound
    while idx < text.endIndex && text[idx].isWhitespace {
      idx = text.index(after: idx)
    }
    guard idx < text.endIndex, text[idx] == ":" else { return nil }
    idx = text.index(after: idx)
    while idx < text.endIndex && text[idx].isWhitespace {
      idx = text.index(after: idx)
    }
    guard idx < text.endIndex, text[idx] == "[" else { return nil }
    let start = idx
    return start..<text.endIndex
  }

  private static func extractJSONArrayElements(from arrayText: String) -> [JSONValue] {
    var elements: [JSONValue] = []
    var current = ""
    var depth = 0
    var inString = false
    var escape = false

    var idx = arrayText.startIndex
    guard idx < arrayText.endIndex, arrayText[idx] == "[" else { return [] }
    idx = arrayText.index(after: idx)

    func finalizeElement() {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      current = ""
      guard !trimmed.isEmpty else { return }
      if let value = try? parseJSONValue(trimmed) {
        elements.append(value)
      }
    }

    while idx < arrayText.endIndex {
      let ch = arrayText[idx]

      if inString {
        current.append(ch)
        if escape {
          escape = false
        } else if ch == "\\" {
          escape = true
        } else if ch == "\"" {
          inString = false
        }
        idx = arrayText.index(after: idx)
        continue
      }

      switch ch {
      case "\"":
        inString = true
        current.append(ch)
      case "{", "[":
        depth += 1
        current.append(ch)
      case "}", "]":
        if depth > 0 {
          depth -= 1
          current.append(ch)
        } else if ch == "]" {
          finalizeElement()
          return elements
        } else {
          current.append(ch)
        }
      case ",":
        if depth == 0 {
          finalizeElement()
        } else {
          current.append(ch)
        }
      default:
        current.append(ch)
      }

      idx = arrayText.index(after: idx)
    }

    return elements
  }

  private static func isEmptyJSONArray(_ arrayText: String) -> Bool {
    var idx = arrayText.startIndex
    guard idx < arrayText.endIndex, arrayText[idx] == "[" else { return false }
    idx = arrayText.index(after: idx)
    while idx < arrayText.endIndex && arrayText[idx].isWhitespace {
      idx = arrayText.index(after: idx)
    }
    return idx < arrayText.endIndex && arrayText[idx] == "]"
  }

  private static func repairJSON(_ text: String) -> String? {
    // Repairs partial/invalid JSON chunks during streaming.
    let fixed = fixJson(input: text.trimmingCharacters(in: .whitespacesAndNewlines))
    return fixed.isEmpty ? nil : fixed
  }

  private enum FixState: Sendable {
    case root
    case finish
    case insideString
    case insideStringEscape
    case insideLiteral
    case insideNumber
    case insideObjectStart
    case insideObjectKey
    case insideObjectAfterKey
    case insideObjectBeforeValue
    case insideObjectAfterValue
    case insideObjectAfterComma
    case insideArrayStart
    case insideArrayAfterValue
    case insideArrayAfterComma
  }

  private static func fixJson(input: String) -> String {
    let chars = Array(input)
    var stack: [FixState] = [.root]
    var lastValidIndex: Int = -1
    var literalStart: Int? = nil

    func processValueStart(char: Character, i: Int, swapState: FixState) {
      switch char {
      case "\"":
        lastValidIndex = i
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideString)

      case "f", "t", "n":
        lastValidIndex = i
        literalStart = i
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideLiteral)

      case "-":
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideNumber)

      case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
        lastValidIndex = i
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideNumber)

      case "{":
        lastValidIndex = i
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideObjectStart)

      case "[":
        lastValidIndex = i
        _ = stack.popLast()
        stack.append(swapState)
        stack.append(.insideArrayStart)

      default:
        break
      }
    }

    func processAfterObjectValue(char: Character, i: Int) {
      switch char {
      case ",":
        _ = stack.popLast()
        stack.append(.insideObjectAfterComma)
      case "}":
        lastValidIndex = i
        _ = stack.popLast()
      default:
        break
      }
    }

    func processAfterArrayValue(char: Character, i: Int) {
      switch char {
      case ",":
        _ = stack.popLast()
        stack.append(.insideArrayAfterComma)
      case "]":
        lastValidIndex = i
        _ = stack.popLast()
      default:
        break
      }
    }

    for i in 0..<chars.count {
      let char = chars[i]
      let currentState = stack.last ?? .root

      switch currentState {
      case .root:
        processValueStart(char: char, i: i, swapState: .finish)

      case .insideObjectStart:
        switch char {
        case "\"":
          _ = stack.popLast()
          stack.append(.insideObjectKey)
        case "}":
          lastValidIndex = i
          _ = stack.popLast()
        default:
          break
        }

      case .insideObjectAfterComma:
        if char == "\"" {
          _ = stack.popLast()
          stack.append(.insideObjectKey)
        }

      case .insideObjectKey:
        if char == "\"" {
          _ = stack.popLast()
          stack.append(.insideObjectAfterKey)
        }

      case .insideObjectAfterKey:
        if char == ":" {
          _ = stack.popLast()
          stack.append(.insideObjectBeforeValue)
        }

      case .insideObjectBeforeValue:
        processValueStart(char: char, i: i, swapState: .insideObjectAfterValue)

      case .insideObjectAfterValue:
        processAfterObjectValue(char: char, i: i)

      case .insideString:
        switch char {
        case "\"":
          _ = stack.popLast()
          lastValidIndex = i
        case "\\":
          stack.append(.insideStringEscape)
        default:
          lastValidIndex = i
        }

      case .insideArrayStart:
        switch char {
        case "]":
          lastValidIndex = i
          _ = stack.popLast()
        default:
          lastValidIndex = i
          processValueStart(char: char, i: i, swapState: .insideArrayAfterValue)
        }

      case .insideArrayAfterValue:
        switch char {
        case ",":
          _ = stack.popLast()
          stack.append(.insideArrayAfterComma)
        case "]":
          lastValidIndex = i
          _ = stack.popLast()
        default:
          lastValidIndex = i
        }

      case .insideArrayAfterComma:
        processValueStart(char: char, i: i, swapState: .insideArrayAfterValue)

      case .insideStringEscape:
        _ = stack.popLast()
        lastValidIndex = i

      case .insideNumber:
        switch char {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
          lastValidIndex = i
        case "e", "E", "-", ".":
          break
        case ",":
          _ = stack.popLast()
          if stack.last == .insideArrayAfterValue {
            processAfterArrayValue(char: char, i: i)
          }
          if stack.last == .insideObjectAfterValue {
            processAfterObjectValue(char: char, i: i)
          }
        case "}":
          _ = stack.popLast()
          if stack.last == .insideObjectAfterValue {
            processAfterObjectValue(char: char, i: i)
          }
        case "]":
          _ = stack.popLast()
          if stack.last == .insideArrayAfterValue {
            processAfterArrayValue(char: char, i: i)
          }
        default:
          _ = stack.popLast()
        }

      case .insideLiteral:
        let start = literalStart ?? 0
        let partialLiteral = String(chars[start...i])

        if !"false".hasPrefix(partialLiteral) &&
          !"true".hasPrefix(partialLiteral) &&
          !"null".hasPrefix(partialLiteral) {
          _ = stack.popLast()

          if stack.last == .insideObjectAfterValue {
            processAfterObjectValue(char: char, i: i)
          } else if stack.last == .insideArrayAfterValue {
            processAfterArrayValue(char: char, i: i)
          }
        } else {
          lastValidIndex = i
        }

      case .finish:
        break
      }
    }

    let prefixCount = max(0, lastValidIndex + 1)
    var result = String(chars.prefix(prefixCount))

    for state in stack.reversed() {
      switch state {
      case .insideString:
        result.append("\"")

      case .insideObjectKey,
           .insideObjectAfterKey,
           .insideObjectAfterComma,
           .insideObjectStart,
           .insideObjectBeforeValue,
           .insideObjectAfterValue:
        result.append("}")

      case .insideArrayStart,
           .insideArrayAfterComma,
           .insideArrayAfterValue:
        result.append("]")

      case .insideLiteral:
        let start = literalStart ?? 0
        if start < chars.count {
          let partialLiteral = String(chars[start..<chars.count])
          if "true".hasPrefix(partialLiteral) {
            result.append(contentsOf: "true".dropFirst(partialLiteral.count))
          } else if "false".hasPrefix(partialLiteral) {
            result.append(contentsOf: "false".dropFirst(partialLiteral.count))
          } else if "null".hasPrefix(partialLiteral) {
            result.append(contentsOf: "null".dropFirst(partialLiteral.count))
          }
        }

      default:
        break
      }
    }

    return result
  }
}

private extension Character {
  var isWhitespace: Bool {
    unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }
}
