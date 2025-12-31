enum ScrollMode: Sendable, Equatable {
  case followBottom
  case pinUserMessageToTop(messageID: String)
}

