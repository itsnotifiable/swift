public protocol Logger: Sendable {
  func debug(_ message: String, context: [String: String])
  func info(_ message: String, context: [String: String])
  func warn(_ message: String, context: [String: String])
  func error(_ message: String, context: [String: String])
}

public struct SilentLogger: Logger {
  public init() {}

  public func debug(_ message: String, context: [String: String]) {}

  public func info(_ message: String, context: [String: String]) {}

  public func warn(_ message: String, context: [String: String]) {}

  public func error(_ message: String, context: [String: String]) {}
}

public protocol KeyValueStore: Sendable {
  func getItem(_ key: String) async -> String?
  func setItem(_ key: String, value: String) async
  func removeItem(_ key: String) async
}

public protocol PushPort: AnyObject, Sendable {
  var provider: PushProvider { get }
  var allowMissingToken: Bool { get }
  func permissionStatus() async -> PermissionStatus
  func requestPermission() async -> PermissionStatus
  func token() async -> String?
  func registrationError() async -> String?
}

extension PushPort {
  public func registrationError() async -> String? {
    nil
  }
}

public protocol DevicePort: Sendable {
  func profile() async -> DeviceProfile
  func applicationId() async -> String?
  func copy(_ value: String)
}

public struct NotifiableConfiguration: Sendable {
  public var publicKey: String
  public var logger: (any Logger)?
  public var push: (any PushPort)?
  public var storage: (any KeyValueStore)?
  public var device: (any DevicePort)?
  public var deepLinks: [DeepLink]?
  public var onDeepLink: (@Sendable (String) -> Void)?

  public init(
    publicKey: String,
    logger: (any Logger)? = nil,
    push: (any PushPort)? = nil,
    storage: (any KeyValueStore)? = nil,
    device: (any DevicePort)? = nil,
    deepLinks: [DeepLink]? = nil,
    onDeepLink: (@Sendable (String) -> Void)? = nil
  ) {
    self.publicKey = publicKey
    self.logger = logger
    self.push = push
    self.storage = storage
    self.device = device
    self.deepLinks = deepLinks
    self.onDeepLink = onDeepLink
  }
}

public struct NotifiableSnapshot: Sendable, Equatable {
  public var ready: Bool
  public var permission: PermissionStatus
  public var subscriber: Subscriber?
  public var clientConfig: DeliveryConfig?
  public var devIndicator: DevIndicatorChoice?
  public var diagnostics: DiagnosticsChoice?
  public var deepLinks: [DeepLink]?
  public var error: NotifiableError?

  public static let initial = NotifiableSnapshot(
    ready: false,
    permission: .notDetermined,
    subscriber: nil,
    clientConfig: nil,
    devIndicator: nil,
    diagnostics: nil,
    deepLinks: nil,
    error: nil
  )
}
