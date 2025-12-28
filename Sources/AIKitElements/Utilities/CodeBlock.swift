import SwiftUI

public struct CodeBlock: View {
  public var text: String
  public var isError: Bool

  public init(_ text: String, isError: Bool = false) {
    self.text = text
    self.isError = isError
  }

  public var body: some View {
    Text(text)
      .font(.system(.caption, design: .monospaced))
      .foregroundStyle(isError ? .red : .secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
  }
}

