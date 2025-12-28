import SwiftUI
import Shimmer

public struct ReasoningDisclosure<Content: View>: View {
  public typealias ThinkingMessageProvider = (_ isStreaming: Bool, _ durationSeconds: Int?) -> AnyView

  public var isStreaming: Bool
  public var open: Binding<Bool>?
  public var defaultOpen: Bool
  public var onOpenChange: ((_ open: Bool) -> Void)?
  public var duration: Binding<Int?>?
  public var getThinkingMessage: ThinkingMessageProvider?

  @ViewBuilder public var content: () -> Content

  @Environment(\.colorScheme) private var colorScheme

  @State private var isOpenState: Bool
  @State private var durationState: Int?
  @State private var hasAutoClosed: Bool = false
  @State private var startTime: Date?
  @State private var autoCloseTask: Task<Void, Never>?

  private let autoCloseDelay: TimeInterval = 1.0

  public init(
    isStreaming: Bool,
    open: Binding<Bool>? = nil,
    defaultOpen: Bool = true,
    onOpenChange: ((_ open: Bool) -> Void)? = nil,
    duration: Binding<Int?>? = nil,
    getThinkingMessage: ThinkingMessageProvider? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.isStreaming = isStreaming
    self.open = open
    self.defaultOpen = defaultOpen
    self.onOpenChange = onOpenChange
    self.duration = duration
    self.getThinkingMessage = getThinkingMessage
    self.content = content
    self._isOpenState = State(initialValue: open?.wrappedValue ?? defaultOpen)
    self._durationState = State(initialValue: duration?.wrappedValue)
  }

  public var body: some View {
    DisclosureGroup(isExpanded: isExpandedBinding) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .foregroundStyle(.secondary)
        .foregroundColor(.secondary)
        .opacity(0.90)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "brain")
        thinkingMessage
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.body)
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .tint(.secondary)
    .padding(.bottom, 16)
    .onAppear {
      scheduleAutoCloseIfNeeded()
    }
    .onChange(of: isStreaming) { newIsStreaming in
      // Track duration when streaming starts and ends.
      if newIsStreaming {
        if startTime == nil {
          startTime = Date()
        }
      } else if let startTime {
        let seconds = Int(ceil(Date().timeIntervalSince(startTime)))
        setDuration(seconds)
        self.startTime = nil
      }

      scheduleAutoCloseIfNeeded()
    }
    .onChange(of: resolvedIsOpen) { _ in
      scheduleAutoCloseIfNeeded()
    }
  }

  private var resolvedIsOpen: Bool { open?.wrappedValue ?? isOpenState }
  private var resolvedDuration: Int? { duration?.wrappedValue ?? durationState }
  private var isExpandedBinding: Binding<Bool> {
    Binding(
      get: { resolvedIsOpen },
      set: { setOpen($0) }
    )
  }

  private func setOpen(_ open: Bool) {
    self.open?.wrappedValue = open
    isOpenState = open
    onOpenChange?(open)
  }

  private func setDuration(_ duration: Int?) {
    self.duration?.wrappedValue = duration
    durationState = duration
  }

  private func scheduleAutoCloseIfNeeded() {
    autoCloseTask?.cancel()
    autoCloseTask = nil

    if defaultOpen, isStreaming == false, resolvedIsOpen, hasAutoClosed == false {
      autoCloseTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(autoCloseDelay * 1_000_000_000))
        guard hasAutoClosed == false else { return }
        setOpen(false)
        hasAutoClosed = true
      }
    }
  }

  @ViewBuilder
  private var thinkingMessage: some View {
    if let getThinkingMessage {
      getThinkingMessage(isStreaming, resolvedDuration)
    } else {
      defaultThinkingMessage(isStreaming: isStreaming, duration: resolvedDuration)
    }
  }

  private func defaultThinkingMessage(isStreaming: Bool, duration: Int?) -> AnyView {
    if isStreaming || duration == 0 {
      return AnyView(
        ZStack(alignment: .leading) {
          Text("Thinking...")
            .foregroundStyle(.secondary)

          Text("Thinking...")
            .foregroundStyle(thinkingShimmerHighlightColor)
            .shimmering()
            .accessibilityHidden(true)
        }
      )
    }
    if duration == nil {
      return AnyView(Text("Thought for a few seconds").foregroundStyle(.secondary))
    }
    return AnyView(Text("Thought for \(duration ?? 0) seconds").foregroundStyle(.secondary))
  }

  private var thinkingShimmerHighlightColor: Color {
    switch colorScheme {
    case .dark:
      return Color.white.opacity(1.0)
    case .light:
      return Color.black.opacity(0.30)
    @unknown default:
      return Color.white.opacity(0.95)
    }
  }
}
