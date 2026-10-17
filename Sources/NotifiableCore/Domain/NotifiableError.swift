public enum NotifiableErrorCode: String, Sendable, Equatable, CaseIterable {
  case invalidConfig = "invalid_config"
  case missingProvider = "missing_provider"
  case notImplemented = "not_implemented"
  case invalidPublicKey = "invalid_public_key"
  case network
  case validationFailed = "validation_failed"
  case subscriberNotFound = "subscriber_not_found"
  case subscriberLimit = "subscriber_limit"
  case rateLimited = "rate_limited"
  case missingToken = "missing_token"
  case missingStorage = "missing_storage"
}

public struct NotifiableError: Error, Sendable, Equatable {
  public let code: NotifiableErrorCode
  public let message: String

  public init(code: NotifiableErrorCode, message: String? = nil) {
    self.code = code
    self.message = message ?? code.rawValue
  }
}

public func asNotifiableError(_ error: Error) -> NotifiableError {
  if let notifiable = error as? NotifiableError {
    return notifiable
  }

  return NotifiableError(code: .network, message: error.localizedDescription)
}
