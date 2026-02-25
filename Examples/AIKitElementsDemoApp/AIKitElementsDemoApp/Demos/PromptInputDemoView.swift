import SwiftUI
import AIKit
import AIKitElements

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct PromptInputDemoView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case idle
    case typing
    case streaming
    case withAttachments
    case bottomBarIdle
    case bottomBarTyping
    case bottomBarStreaming
    case bottomBarWithAttachments

    var id: String { rawValue }

    var showsExpandedBottomBar: Bool {
      switch self {
      case .bottomBarIdle, .bottomBarTyping, .bottomBarStreaming, .bottomBarWithAttachments:
        return true
      case .idle, .typing, .streaming, .withAttachments:
        return false
      }
    }

    var promptStatus: ChatStatus {
      switch self {
      case .streaming, .bottomBarStreaming:
        return .streaming
      case .idle, .typing, .withAttachments, .bottomBarIdle, .bottomBarTyping, .bottomBarWithAttachments:
        return .ready
      }
    }
  }

  let mode: Mode
  @State private var text: String = ""
  @State private var attachments: [ChatFilePart] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("This is a single glass surface (chrome). Message content should stay non-glass.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Group {
        if mode.showsExpandedBottomBar {
          PromptInput(
            text: $text,
            status: mode.promptStatus,
            attachments: attachments,
            onSend: { _ in },
            onStop: { },
            expandedBottomBar: {
            HStack(spacing: 8) {
              circleButton(symbol: "plus")
              circleButton(symbol: "magnifyingglass")
              circleButton(symbol: "mic.fill")
            }
            }
	          )
        } else {
          PromptInput(
            text: $text,
            status: mode.promptStatus,
            attachments: attachments,
            onSend: { _ in },
            onStop: { }
          )
        }
      }
      .onAppear {
        switch mode {
        case .idle:
          text = ""
          attachments = []
        case .typing:
          text = "Hello from the composer"
          attachments = []
        case .streaming:
          text = "Streaming…"
          attachments = []
        case .withAttachments:
          text = "A message with attachments"
          attachments = sampleAttachments
        case .bottomBarIdle:
          text = ""
          attachments = []
        case .bottomBarTyping:
          text = "Hello from the composer"
          attachments = []
        case .bottomBarStreaming:
          text = "Streaming…"
          attachments = []
        case .bottomBarWithAttachments:
          text = ""
          attachments = sampleAttachments
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func circleButton(symbol: String) -> some View {
    Button {} label: {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .frame(width: 34, height: 34)
        .foregroundStyle(.primary)
        .background(Color.gray.opacity(0.15), in: .circle)
    }
    .buttonStyle(.plain)
  }

  private var sampleAttachments: [ChatFilePart] {
    [
      .init(data: .data(demoSymbolData("photo") ?? Data()), filename: "Image.png", mediaType: "image/png"),
      .init(data: .data(demoSymbolData("doc") ?? Data()), filename: "Notes.pdf", mediaType: "application/pdf"),
    ]
  }
}

#if canImport(AppKit)
private func demoSymbolData(_ name: String) -> Data? {
  guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff) else { return nil }
  return rep.representation(using: .png, properties: [:])
}
#elseif canImport(UIKit)
private func demoSymbolData(_ name: String) -> Data? {
  UIImage(systemName: name)?.pngData()
}
#else
private func demoSymbolData(_ name: String) -> Data? {
  nil
}
#endif
