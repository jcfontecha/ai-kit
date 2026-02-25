import SwiftUI
import AIKitElements

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

      ApprovalBanner(
        state: state.bannerState,
        message: state == .requested ? "This tool wants to delete `/tmp/example.txt`. Do you approve?" : nil,
        onApprove: state == .requested ? {} : nil,
        onReject: state == .requested ? {} : nil
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private enum ApprovalState: Hashable {
  case requested
  case approved
  case rejected

  var bannerState: ApprovalBannerState {
    switch self {
    case .requested: .requested
    case .approved: .approved
    case .rejected: .rejected
    }
  }
}
