import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class CollectToolApprovalsTests: XCTestCase {
  private func toolCall(id: String) -> ToolCall {
    ToolCall(toolCallID: id, toolName: "tool1", inputJSON: "{\"value\":\"test-input\"}")
  }

  func testCollectToolApprovals_lastMessageNotToolReturnsEmpty() throws {
    let result = try collectToolApprovals(
      messages: [.user("Hello, world!")]
    )

    XCTAssertEqual(result.approvedToolApprovals, [])
    XCTAssertEqual(result.deniedToolApprovals, [])
  }

  func testCollectToolApprovals_ignoresApprovalRequestWithoutResponse() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
          ]
        ),
        .init(role: .tool, content: [])
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals, [])
    XCTAssertEqual(result.deniedToolApprovals, [])
  }

  func testCollectToolApprovals_returnsApproved() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
          ]
        ),
        .init(
          role: .tool,
          content: [
            .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: true)),
          ]
        ),
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals.count, 1)
    XCTAssertEqual(result.deniedToolApprovals.count, 0)
    let approved = result.approvedToolApprovals[0]
    XCTAssertEqual(approved.approvalRequest.approvalID, "approval-id-1")
    XCTAssertEqual(approved.approvalResponse.approvalID, "approval-id-1")
    XCTAssertEqual(approved.toolCall.toolCallID, "call-1")
  }

  func testCollectToolApprovals_processedApprovalWithToolResultReturnsEmpty() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
          ]
        ),
        .init(
          role: .tool,
          content: [
            .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: true)),
            .toolResult(
              ToolResult(
                toolCallID: "call-1",
                toolName: "tool1",
                output: .object(["type": .string("text"), "value": .string("test-output")])
              )
            ),
          ]
        ),
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals, [])
    XCTAssertEqual(result.deniedToolApprovals, [])
  }

  func testCollectToolApprovals_returnsDenied() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
          ]
        ),
        .init(
          role: .tool,
          content: [
            .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: false, reason: "test-reason")),
          ]
        ),
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals.count, 0)
    XCTAssertEqual(result.deniedToolApprovals.count, 1)
    let denied = result.deniedToolApprovals[0]
    XCTAssertEqual(denied.approvalRequest.approvalID, "approval-id-1")
    XCTAssertEqual(denied.approvalResponse.approvalID, "approval-id-1")
    XCTAssertEqual(denied.approvalResponse.reason, "test-reason")
    XCTAssertEqual(denied.toolCall.toolCallID, "call-1")
  }

  func testCollectToolApprovals_deniedWithToolOutputDeniedReturnsEmpty() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
          ]
        ),
        .init(
          role: .tool,
          content: [
            .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: false, reason: "test-reason")),
            .toolOutputDenied(.init(toolCallID: "call-1", toolName: "tool1")),
          ]
        ),
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals, [])
    XCTAssertEqual(result.deniedToolApprovals, [])
  }

  func testCollectToolApprovals_unknownApprovalIDThrows() {
    XCTAssertThrowsError(
      try collectToolApprovals(
        messages: [
          .init(
            role: .assistant,
            content: [
              .toolCall(toolCall(id: "call-1")),
              .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-1")),
            ]
          ),
          .init(
            role: .tool,
            content: [
              .toolApprovalResponse(.init(approvalID: "unknown-approval-id", approved: true)),
            ]
          ),
        ]
      )
    ) { error in
      XCTAssertEqual(
        (error as? ToolApprovalCollectionError)?.message,
        "Tool approval response references unknown approvalId: \"unknown-approval-id\""
      )
    }
  }

  func testCollectToolApprovals_missingToolCallThrows() {
    XCTAssertThrowsError(
      try collectToolApprovals(
        messages: [
          .init(
            role: .assistant,
            content: [
              .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "missing-call")),
            ]
          ),
          .init(
            role: .tool,
            content: [
              .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: true)),
            ]
          ),
        ]
      )
    ) { error in
      XCTAssertEqual(
        (error as? ToolApprovalCollectionError)?.message,
        "Tool call \"missing-call\" not found for approval request \"approval-id-1\"."
      )
    }
  }

  func testCollectToolApprovals_multipleApprovalsMixedResults() throws {
    let result = try collectToolApprovals(
      messages: [
        .init(
          role: .assistant,
          content: [
            .toolCall(toolCall(id: "call-approval-1")),
            .toolApprovalRequest(.init(approvalID: "approval-id-1", toolCallID: "call-approval-1")),
            .toolCall(toolCall(id: "call-approval-2")),
            .toolApprovalRequest(.init(approvalID: "approval-id-2", toolCallID: "call-approval-2")),
            .toolCall(toolCall(id: "call-approval-3")),
            .toolApprovalRequest(.init(approvalID: "approval-id-3", toolCallID: "call-approval-3")),
            .toolCall(toolCall(id: "call-approval-4")),
            .toolApprovalRequest(.init(approvalID: "approval-id-4", toolCallID: "call-approval-4")),
            .toolCall(toolCall(id: "call-approval-5")),
            .toolApprovalRequest(.init(approvalID: "approval-id-5", toolCallID: "call-approval-5")),
            .toolCall(toolCall(id: "call-approval-6")),
            .toolApprovalRequest(.init(approvalID: "approval-id-6", toolCallID: "call-approval-6")),
          ]
        ),
        .init(
          role: .tool,
          content: [
            .toolApprovalResponse(.init(approvalID: "approval-id-1", approved: true)),
            .toolApprovalResponse(.init(approvalID: "approval-id-2", approved: true)),
            .toolApprovalResponse(.init(approvalID: "approval-id-3", approved: false, reason: "test-reason")),
            .toolApprovalResponse(.init(approvalID: "approval-id-4", approved: false)),
            .toolApprovalResponse(.init(approvalID: "approval-id-5", approved: true)),
            .toolResult(
              ToolResult(
                toolCallID: "call-approval-5",
                toolName: "tool1",
                output: .object(["type": .string("text"), "value": .string("test-output-5")])
              )
            ),
            .toolApprovalResponse(.init(approvalID: "approval-id-6", approved: false)),
            .toolOutputDenied(.init(toolCallID: "call-approval-6", toolName: "tool1")),
          ]
        ),
      ]
    )

    XCTAssertEqual(result.approvedToolApprovals.count, 2)
    XCTAssertEqual(result.deniedToolApprovals.count, 2)
  }
}
