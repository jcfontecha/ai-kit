import Foundation

/// Minimal `multipart/form-data` encoder for OpenAI endpoints that accept file
/// uploads (image edits, audio transcriptions).
struct OpenAIMultipartForm {
  private enum Part {
    case field(name: String, value: String)
    case file(name: String, filename: String, contentType: String, data: Data)
  }

  private var parts: [Part] = []
  let boundary: String

  init(boundary: String = "----AIKitFormBoundary\(UUID().uuidString)") {
    self.boundary = boundary
  }

  var contentType: String {
    "multipart/form-data; boundary=\(boundary)"
  }

  mutating func addField(name: String, value: String) {
    parts.append(.field(name: name, value: value))
  }

  mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
    parts.append(.file(name: name, filename: filename, contentType: contentType, data: data))
  }

  func encode() -> Data {
    var body = Data()
    let prefix = "--\(boundary)\r\n"

    for part in parts {
      body.append(prefix)
      switch part {
      case .field(let name, let value):
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
      case .file(let name, let filename, let contentType, let data):
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
      }
    }

    body.append("--\(boundary)--\r\n")
    return body
  }
}

private extension Data {
  mutating func append(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }
}
