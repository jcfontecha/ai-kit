import CryptoKit
import Foundation

protocol OpenClawWebSocket: Sendable {
  func send(text: String) async throws
  func receiveText() async throws -> String
  func close() async
}

final class OpenClawPinnedTLSDelegate: NSObject, URLSessionDelegate {
  private let expectedFingerprint: String?

  init(expectedFingerprint: String?) {
    self.expectedFingerprint = expectedFingerprint.flatMap { normalizeFingerprint($0) }
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let expectedFingerprint
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }

    guard let trust = challenge.protectionSpace.serverTrust,
          let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
          let cert = chain.first
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }

    let certData = SecCertificateCopyData(cert) as Data
    let digest = SHA256.hash(data: certData)
    let actualFingerprint = normalizeFingerprint(digest.map { String(format: "%02x", $0) }.joined())

    guard actualFingerprint == expectedFingerprint else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }

    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}

private func normalizeFingerprint(_ input: String) -> String {
  input.lowercased().filter { $0.isHexDigit }
}

actor OpenClawURLSessionWebSocket: OpenClawWebSocket {
  private static let defaultMaximumMessageSize = 25 * 1024 * 1024

  private let session: URLSession
  private let task: URLSessionWebSocketTask

  init(url: URL, tlsFingerprintSHA256: String?) {
    let delegate = OpenClawPinnedTLSDelegate(expectedFingerprint: tlsFingerprintSHA256)
    self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    self.task = session.webSocketTask(with: url)
    self.task.maximumMessageSize = Self.defaultMaximumMessageSize
    self.task.resume()
  }

  func send(text: String) async throws {
    try await task.send(.string(text))
  }

  func receiveText() async throws -> String {
    let message = try await task.receive()
    switch message {
    case .string(let text):
      return text
    case .data(let data):
      guard let text = String(data: data, encoding: .utf8) else {
        throw OpenClawGatewayError.invalidJSON("Received non-UTF8 data")
      }
      return text
    @unknown default:
      throw OpenClawGatewayError.invalidJSON("Received unknown WebSocket message")
    }
  }

  func close() async {
    task.cancel(with: .normalClosure, reason: nil)
    session.invalidateAndCancel()
  }
}
