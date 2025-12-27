import SwiftUI

struct ConfirmationDemoView: View {
  @State private var state: ApprovalState = .requested

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("State", selection: $state) {
        Text("Requested").tag(ApprovalState.requested)
        Text("Approved").tag(ApprovalState.approved)
        Text("Rejected").tag(ApprovalState.rejected)
      }
      .pickerStyle(.segmented)

      ApprovalBanner(state: state)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private enum ApprovalState: Hashable {
  case requested
  case approved
  case rejected
}

private struct ApprovalBanner: View {
  let state: ApprovalState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle")
        Text("Approval required").font(.headline)
        Spacer()
      }

      switch state {
      case .requested:
        Text("This tool wants to delete `/tmp/example.txt`. Do you approve?")
          .foregroundStyle(.secondary)
        HStack(spacing: 10) {
          Button("Reject") {}
            .buttonStyle(.bordered)
          Button("Approve") {}
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
    .glassSurface(
      cornerRadius: 16,
      interactive: false,
      tint: state == .requested ? Color.yellow.opacity(0.10) : (state == .approved ? Color.green.opacity(0.10) : Color.red.opacity(0.10))
    )
  }
}

