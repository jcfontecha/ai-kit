import Foundation
import AIKitProviders

let openRouterAudioFormats: [OpenRouterAudioFormat] = [
  .wav,
  .mp3,
  .aiff,
  .aac,
  .ogg,
  .flac,
  .m4a,
  .pcm16,
  .pcm24,
]

let openRouterMimeToFormat: [String: OpenRouterAudioFormat] = [
  "mpeg": .mp3,
  "mp3": .mp3,
  "x-wav": .wav,
  "wave": .wav,
  "wav": .wav,
  "ogg": .ogg,
  "vorbis": .ogg,
  "aac": .aac,
  "x-aac": .aac,
  "m4a": .m4a,
  "x-m4a": .m4a,
  "mp4": .m4a,
  "aiff": .aiff,
  "x-aiff": .aiff,
  "flac": .flac,
  "x-flac": .flac,
  "pcm16": .pcm16,
  "pcm24": .pcm24,
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

func getInputAudioData(file: FileContent) throws -> OpenRouterInputAudio {
  let mediaType = file.mediaType ?? "audio/mpeg"
  let fileData = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "audio/mpeg")

  if isURLString(fileData, protocols: ["http", "https"]) {
    throw OpenRouterInvalidResponseError(
      message:
        "Audio files cannot be provided as URLs.\n\n" +
        "OpenRouter requires audio to be base64-encoded. Please:\n" +
        "1. Download the audio file locally\n" +
        "2. Read it as a Buffer or Uint8Array\n" +
        "3. Pass it as the data parameter\n\n" +
        "The will automatically handle base64 encoding.\n\n" +
        "Learn more: https://openrouter.ai/docs/features/multimodal/audio"
    )
  }

  let data = getBase64FromDataUrl(fileData)
  let rawFormat = mediaType.replacingOccurrences(of: "audio/", with: "")
  guard let format = openRouterMimeToFormat[rawFormat] else {
    let supported = openRouterAudioFormats.map { $0.rawValue }.joined(separator: ", ")
    throw OpenRouterInvalidResponseError(
      message:
        "Unsupported audio format: \"\(mediaType)\"\n\n" +
        "OpenRouter supports the following audio formats: \(supported)\n\n" +
        "Learn more: https://openrouter.ai/docs/features/multimodal/audio"
    )
  }

  return OpenRouterInputAudio(data: data, format: format)
}

func isURLString(_ value: String, protocols: [String]) -> Bool {
  guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
  return protocols.contains(scheme)
}
