import Foundation
import AIKitProviders

func prepareMessagesForModel(
  messages: [ModelMessage],
  model: any LanguageModel,
  download: DownloadFunction?
) async throws -> [ModelMessage] {
  let downloadPlan = planDownloads(messages: messages, supportedURLs: model.supportedURLs)
  let downloadedAssets = try await downloadAssets(plan: downloadPlan, download: download)

  return try messages.map { message in
    let shouldNormalize = (message.role == .user || message.role == .assistant)
    guard shouldNormalize else { return message }
    let updatedContent = try message.content.map { part -> ModelMessagePart in
      switch part {
      case .image(let content):
        return .image(try normalizeImageContent(content, downloadedAssets: downloadedAssets))
      case .file(let content):
        return .file(try normalizeFileContent(content, downloadedAssets: downloadedAssets))
      default:
        return part
      }
    }
    .filter { part in
      if case let .text(textPart) = part {
        return textPart.text.isEmpty == false
      }
      return true
    }
    return ModelMessage(
      role: message.role,
      content: updatedContent,
      providerOptions: message.providerOptions,
      providerMetadata: message.providerMetadata
    )
  }
}

private struct PlannedDownload {
  let request: DownloadRequest
  let urlString: String
}

private func planDownloads(
  messages: [ModelMessage],
  supportedURLs: SupportedURLPatterns
) -> [PlannedDownload] {
  var planned: [PlannedDownload] = []

  for message in messages where message.role == .user {
    for part in message.content {
      switch part {
      case .image(let content):
        guard case let .url(url) = content.data else { continue }
        guard url.scheme?.lowercased() != "data" else { continue }
        let mediaType = content.mediaType ?? "image/*"
        let isSupported = isURLSupported(
          mediaType: mediaType,
          url: url.absoluteString,
          supportedURLs: supportedURLs
        )
        planned.append(
          .init(
            request: .init(url: url, isURLSupportedByModel: isSupported),
            urlString: url.absoluteString
          )
        )
      case .file(let content):
        guard case let .url(url) = content.data else { continue }
        guard url.scheme?.lowercased() != "data" else { continue }
        let mediaType = content.mediaType
        let isSupported = mediaType.map {
          isURLSupported(mediaType: $0, url: url.absoluteString, supportedURLs: supportedURLs)
        } ?? false
        planned.append(
          .init(
            request: .init(url: url, isURLSupportedByModel: isSupported),
            urlString: url.absoluteString
          )
        )
      default:
        continue
      }
    }
  }

  return planned
}

private func downloadAssets(
  plan: [PlannedDownload],
  download: DownloadFunction?
) async throws -> [String: DownloadedAsset] {
  guard let download, plan.isEmpty == false else { return [:] }
  let requests = plan.map { $0.request }
  let results = try await download(requests)
  var assets: [String: DownloadedAsset] = [:]
  for (index, result) in results.enumerated() {
    guard let result else { continue }
    assets[plan[index].urlString] = result
  }
  return assets
}

private func normalizeImageContent(
  _ content: ImageContent,
  downloadedAssets: [String: DownloadedAsset]
) throws -> ImageContent {
  let (data, mediaType) = try normalizeDataContent(
    content.data,
    mediaType: content.mediaType,
    downloadedAssets: downloadedAssets
  )

  let detected = detectImageMediaType(from: data)

  return ImageContent(
    data: data,
    mediaType: detected ?? mediaType ?? "image/*",
    providerOptions: content.providerOptions
  )
}

private func normalizeFileContent(
  _ content: FileContent,
  downloadedAssets: [String: DownloadedAsset]
) throws -> FileContent {
  guard let requiredMediaType = content.mediaType else {
    throw AIKitError.invalidConfiguration("Media type is missing for file part.")
  }

  let (data, mediaType) = try normalizeDataContent(
    content.data,
    mediaType: requiredMediaType,
    downloadedAssets: downloadedAssets
  )

  guard let mediaType else {
    throw AIKitError.invalidConfiguration("Media type is missing for file part.")
  }

  return FileContent(
    data: data,
    filename: content.filename,
    mediaType: mediaType,
    providerOptions: content.providerOptions
  )
}

private func normalizeDataContent(
  _ content: DataContent,
  mediaType: String?,
  downloadedAssets: [String: DownloadedAsset]
) throws -> (DataContent, String?) {
  switch content {
  case .data, .base64:
    return (content, mediaType)
  case .url(let url):
    if url.scheme?.lowercased() == "data" {
      let parsed = try splitDataURL(url.absoluteString)
      guard let base64 = parsed.base64 else {
        throw AIKitError.invalidConfiguration("Invalid data URL format: \(url.absoluteString)")
      }
      return (.base64(base64), mediaType ?? parsed.mediaType)
    }

    if let downloaded = downloadedAssets[url.absoluteString] {
      return (.data(downloaded.data), mediaType ?? downloaded.mediaType)
    }

    return (.url(url), mediaType)
  }
}

private func detectImageMediaType(from content: DataContent) -> String? {
  switch content {
  case .data(let data):
    return detectImageMediaType(data: data)
  case .base64(let base64):
    guard let data = Data(base64Encoded: base64) else { return nil }
    return detectImageMediaType(data: data)
  case .url:
    return nil
  }
}

private func detectImageMediaType(data: Data) -> String? {
  let bytes = [UInt8](data)
  if bytes.count >= 8,
     bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
     bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
    return "image/png"
  }
  if bytes.count >= 3,
     bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
    return "image/jpeg"
  }
  if bytes.count >= 6 {
    let header = String(bytes: bytes.prefix(6), encoding: .ascii)
    if header == "GIF87a" || header == "GIF89a" {
      return "image/gif"
    }
  }
  if bytes.count >= 12 {
    let riff = String(bytes: bytes.prefix(4), encoding: .ascii)
    let webp = String(bytes: bytes.dropFirst(8).prefix(4), encoding: .ascii)
    if riff == "RIFF" && webp == "WEBP" {
      return "image/webp"
    }
  }
  return nil
}

private func splitDataURL(_ urlString: String) throws -> (mediaType: String?, base64: String?) {
  guard let commaIndex = urlString.firstIndex(of: ",") else {
    return (nil, nil)
  }

  let header = String(urlString[..<commaIndex])
  let content = String(urlString[urlString.index(after: commaIndex)...])

  let mediaType = header
    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
    .first?
    .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
    .last
    .map(String.init)

  return (mediaType, content.isEmpty ? nil : content)
}
