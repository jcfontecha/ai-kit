import Foundation

struct OpenRouterAPIError: LocalizedError, Equatable {
  let message: String
  let statusCode: Int?

  var errorDescription: String? { message }
}

struct OpenRouterInvalidResponseError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenRouterInvalidArgumentError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenRouterUnsupportedFunctionalityError: LocalizedError, Equatable {
  let functionality: String

  var errorDescription: String? {
    "Unsupported functionality: \(functionality)"
  }
}
