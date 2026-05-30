import Foundation
import AIKitProviders

let openAIAudioFormats: [OpenAIAudioFormat] = [
  .wav,
  .mp3,
]

let openAIMimeToFormat: [String: OpenAIAudioFormat] = [
  "mpeg": .mp3,
  "mp3": .mp3,
  "x-wav": .wav,
  "wave": .wav,
  "wav": .wav,
]

func getFileUrl(part: DataContent, mediaType: String, defaultMediaType: String) -> String {
  switch part {
  case .data(let data):
    let base64 = data.base64EncodedString()
    return "data:\(mediaType.isEmpty ? defaultMediaType : mediaType);base64,\(base64)"
  case .base64(let base64):
    if base64.starts(with: "data:") {
      return base64
    }
    return "data:\(mediaType.isEmpty ? defaultMediaType : mediaType);base64,\(base64)"
  case .url(let url):
    return url.absoluteString
  }
}

func getMediaType(from dataUrl: String, defaultMediaType: String) -> String {
  let prefix = "data:"
  guard dataUrl.hasPrefix(prefix) else { return defaultMediaType }
  let withoutPrefix = dataUrl.dropFirst(prefix.count)
  if let semiIndex = withoutPrefix.firstIndex(of: ";") {
    return String(withoutPrefix[..<semiIndex])
  }
  return defaultMediaType
}

func getBase64FromDataUrl(_ dataUrl: String) -> String {
  guard let range = dataUrl.range(of: "base64,") else {
    return dataUrl
  }
  return String(dataUrl[range.upperBound...])
}

func getInputAudioData(file: FileContent) throws -> OpenAIInputAudio {
  let mediaType = file.mediaType ?? "audio/mpeg"
  let fileData = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "audio/mpeg")

  if isURLString(fileData, protocols: ["http", "https"]) {
    throw OpenAIInvalidResponseError(
      message:
        "Audio files cannot be provided as URLs. " +
        "OpenAI requires audio to be base64-encoded."
    )
  }

  let data = getBase64FromDataUrl(fileData)
  let rawFormat = mediaType.replacingOccurrences(of: "audio/", with: "")
  guard let format = openAIMimeToFormat[rawFormat] else {
    let supported = openAIAudioFormats.map { $0.rawValue }.joined(separator: ", ")
    throw OpenAIInvalidResponseError(
      message: "Unsupported audio format: \"\(mediaType)\". OpenAI supports: \(supported)"
    )
  }

  return OpenAIInputAudio(data: data, format: format)
}

func isURLString(_ value: String, protocols: [String]) -> Bool {
  guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
  return protocols.contains(scheme)
}
