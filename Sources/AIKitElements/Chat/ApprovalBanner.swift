import SwiftUI

public enum ApprovalBannerState: Hashable, Sendable {
  case requested
  case approved
  case rejected
}

public struct ApprovalBanner: View {
  public var state: ApprovalBannerState
  public var title: String
  public var message: String?
  public var onApprove: (() -> Void)?
  public var onReject: (() -> Void)?

  public init(
    state: ApprovalBannerState,
    title: String = "Approval required",
    message: String? = nil,
    onApprove: (() -> Void)? = nil,
    onReject: (() -> Void)? = nil
  ) {
    self.state = state
    self.title = title
    self.message = message
    self.onApprove = onApprove
    self.onReject = onReject
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle")
        Text(title).font(.headline)
        Spacer()
      }

      switch state {
      case .requested:
        if let message {
          Text(message)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 10) {
          Button("Reject") { onReject?() }
            .buttonStyle(.bordered)
          Button("Approve") { onApprove?() }
            .buttonStyle(.borderedProminent)
        }

      case .approved:
        Label("Approved", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)

      case .rejected:
        Label("Rejected", systemImage: "xmark.octagon.fill")
          .foregroundStyle(.red)
      }
    }
    .padding(12)
    .glassSurface(cornerRadius: 16, interactive: false, tint: tint)
  }

  private var tint: Color? {
    switch state {
    case .requested:
      return Color.yellow.opacity(0.10)
    case .approved:
      return Color.green.opacity(0.10)
    case .rejected:
      return Color.red.opacity(0.10)
    }
  }
}

