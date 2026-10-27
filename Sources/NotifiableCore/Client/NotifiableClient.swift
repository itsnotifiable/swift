import Combine
import Foundation

@MainActor
public final class NotifiableClient: ObservableObject {
  public let configuration: NotifiableConfiguration
  @Published public private(set) var snapshot: NotifiableSnapshot = .initial

  private let api: SdkAPI
  private let device: any DevicePort
  private let logger: any Logger
  private var storage: any KeyValueStore
  private var session: StoredSession?
  private var diagnosticsChoice: DiagnosticsChoice?
  private var diagnosticQueue: [PendingDiagnostic] = []
  private var diagnosticSeen = Set<String>()
  private var diagnosticFlushing = false
  private var chain: Task<Void, Never> = Task {}

  public init(
    publicKey: String,
    logger: (any Logger)? = nil,
    push: (any PushPort)? = nil,
    storage: (any KeyValueStore)? = nil,
    device: (any DevicePort)? = nil,
    deepLinks: [DeepLink]? = nil,
    onDeepLink: (@Sendable (String) -> Void)? = nil,
    transport: (any HTTPSending)? = nil
  ) throws {
    installLinkedApplePlatform()
    let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)

    if key.isEmpty {
      throw NotifiableError(code: .invalidConfig, message: "publicKey is required")
    }

    installLinkedApplePlatform()
    let resolvedDevice = device ?? NotifiablePlatformRegistry.makeDevice()

    guard let resolvedDevice else {
      throw NotifiableError(
        code: .invalidConfig,
        message: "Notifiable could not read this device."
      )
    }

    let resolvedPush = push ?? NotifiablePlatformRegistry.makePush()
    self.configuration = NotifiableConfiguration(
      publicKey: key,
      logger: logger,
      push: resolvedPush,
      storage: storage,
      device: resolvedDevice,
      deepLinks: deepLinks,
      onDeepLink: onDeepLink
    )
    self.api = SdkAPI(
      http: HTTPClient(
        baseURL: notifiableAPIURL,
        publicKey: key,
        transport: transport ?? URLSessionHTTP()
      )
    )
    self.device = resolvedDevice
    self.logger = logger ?? SilentLogger()
    self.storage = storage ?? UserDefaultsStorage()
    self.logger.debug(
      "Notifiable client created",
      context: ["hasPush": resolvedPush == nil ? "false" : "true"]
    )
  }

  public func start() async throws {
    try await enqueue {
      try await self.performStart()
    }
  }

  @discardableResult
  public func requestPermission() async throws -> PermissionStatus {
    try await enqueue {
      try await self.performStart()
      return try await self.performRequestPermission()
    }
  }

  @discardableResult
  public func identify(
    email: String? = nil,
    externalId: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil
  ) async throws -> Subscriber {
    try await identify(
      IdentifyInput(
        email: email,
        externalId: externalId,
        firstName: firstName,
        lastName: lastName,
        includesFirstName: firstName != nil,
        includesLastName: lastName != nil
      )
    )
  }

  @discardableResult
  public func identify(_ input: IdentifyInput) async throws -> Subscriber {
    try await enqueue {
      try await self.performStart()
      return try await self.performIdentify(input)
    }
  }

  public func setDevIndicator(enabled: Bool) async {
    let storage = await resolveStorage()
    let choice: DevIndicatorChoice = enabled ? .enabled : .disabled
    await saveChoice(
      storage: storage,
      key: devIndicatorKey(configuration.publicKey),
      value: choice.rawValue
    )
    commit(devIndicator: choice)
  }

  public func setDiagnostics(enabled: Bool) async {
    let storage = await resolveStorage()
    let choice: DiagnosticsChoice = enabled ? .enabled : .disabled
    await saveChoice(
      storage: storage,
      key: diagnosticsKey(configuration.publicKey),
      value: choice.rawValue
    )
    diagnosticsChoice = choice
    commit(diagnostics: choice)

    if !enabled {
      diagnosticQueue = []
    }
  }

  public func listNotifications(
    subscriberId: String,
    query: InboxQuery? = nil
  ) async throws -> InboxPage {
    try await capture {
      try await self.api.listNotifications(subscriberId: subscriberId, query: query)
    }
  }

  public func inbox(query: InboxQuery? = nil) async throws -> InboxPage {
    let subscriberId = try requireSubscriberId()
    return try await listNotifications(subscriberId: subscriberId, query: query)
  }

  public func notification(_ notificationId: String) async throws -> SubscriberNotification {
    let subscriberId = try requireSubscriberId()
    return try await capture {
      try await self.api.getNotification(
        subscriberId: subscriberId,
        notificationId: notificationId
      )
    }
  }

  public func openNotification(_ notificationId: String) async throws {
    let subscriberId = try requireSubscriberId()
    try await capture {
      try await self.api.openNotification(
        subscriberId: subscriberId,
        notificationId: notificationId
      )
    }
  }

  public func clickDelivery(_ deliveryId: String) async throws {
    try await capture {
      try await self.api.clickDelivery(deliveryId: deliveryId)
    }
  }

  @discardableResult
  public func track(
    name: String,
    properties: [String: EventProperty]? = nil
  ) async throws -> RecordedEvent {
    let subscriberId = try requireSubscriberId()
    return try await capture {
      try await self.api.trackEvent(
        subscriberId: subscriberId,
        name: name,
        properties: properties
      )
    }
  }

  private func enqueue<T>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
    let previous = chain
    let task = Task { @MainActor () throws -> T in
      await previous.value
      return try await work()
    }
    chain = Task { @MainActor in
      _ = try? await task.value
    }
    return try await task.value
  }

  private func performStart() async throws {
    if snapshot.ready {
      return
    }

    try await guardRun {
      let storage = await self.resolveStorage()
      let existing = await loadSession(storage: storage, publicKey: self.configuration.publicKey)
      let session = existing ?? StoredSession(
        deviceId: createId(),
        subscriberId: nil,
        pushToken: nil,
        anonymousId: nil
      )

      if existing == nil {
        await saveSession(
          storage: storage,
          publicKey: self.configuration.publicKey,
          session: session
        )
      }

      self.session = session
      let devIndicator: DevIndicatorChoice? = await loadChoice(
        storage: storage,
        key: devIndicatorKey(self.configuration.publicKey)
      )
      let diagnostics: DiagnosticsChoice? = await loadChoice(
        storage: storage,
        key: diagnosticsKey(self.configuration.publicKey)
      )
      self.diagnosticsChoice = diagnostics
      let clientConfig = try await self.api.getClientConfig()
      self.commit(clientConfig: clientConfig, devIndicator: devIndicator, diagnostics: diagnostics)
      try await self.syncDevice(prompted: false, permission: nil)
      try await self.saveDeepLinks()
      try await self.promptIfRequested()
    }
  }

  private func promptIfRequested() async throws {
    guard snapshot.subscriber?.promptPermission == true, configuration.push != nil else {
      return
    }

    logger.info("Permission prompt requested", context: [:])
    // Dashboard prompts must clear even when a token cannot be created.
    _ = try await performRequestPermission(requireToken: false)
  }

  private func performRequestPermission(requireToken: Bool = true) async throws -> PermissionStatus {
    try await guardRun {
      guard self.configuration.push != nil else {
        throw NotifiableError(
          code: .invalidConfig,
          message: "push is required to request permission."
        )
      }

      let permission = await self.configuration.push!.requestPermission()
      try await self.syncDevice(
        prompted: true,
        permission: permission,
        requireToken: requireToken && permission == .granted
      )
      return self.snapshot.permission
    }
  }

  private func performIdentify(_ input: IdentifyInput) async throws -> Subscriber {
    try await guardRun {
      let session = try self.requireSession()

      guard let subscriberId = session.subscriberId else {
        throw NotifiableError(
          code: .subscriberNotFound,
          message: "The subscriber is not registered yet."
        )
      }

      let identity = try identityFrom(input)
      let subscriber = try await self.api.updateSubscriber(
        subscriberId: subscriberId,
        identity: identity
      )
      let storage = await self.resolveStorage()
      let next = StoredSession(
        deviceId: session.deviceId,
        subscriberId: subscriber.id,
        pushToken: session.pushToken,
        anonymousId: subscriber.anonymousId
      )
      await saveSession(storage: storage, publicKey: self.configuration.publicKey, session: next)
      self.session = next
      self.commit(subscriber: subscriber, error: .some(nil))
      self.logger.info("Subscriber identified", context: ["subscriberId": subscriber.id])
      return subscriber
    }
  }

  private func syncDevice(
    prompted: Bool,
    permission override: PermissionStatus?,
    requireToken: Bool = false
  ) async throws {
    var session = try requireSession()

    if session.subscriberId == nil && session.anonymousId == nil {
      session.anonymousId = createId()
      let storage = await resolveStorage()
      await saveSession(storage: storage, publicKey: configuration.publicKey, session: session)
      self.session = session
    }

    let profile = await device.profile()
    let permission: PermissionStatus

    if let override {
      permission = override
    } else {
      permission = await currentPermission()
    }
    let token = try await tokenFor(permission, requireToken: requireToken)
    let savedPermission: PermissionStatus =
      token == nil && permission == .granted ? .notDetermined : permission
    let anonymousId = session.subscriberId == nil ? session.anonymousId : nil
    let place = localeParts(profile.locale)
    let write = SubscriberWrite(
      deviceId: session.deviceId,
      platform: profile.platform,
      permission: savedPermission,
      provider: token?.provider,
      token: token?.token,
      anonymousId: anonymousId,
      prompted: prompted ? true : nil,
      osVersion: profile.osVersion,
      locale: profile.locale,
      timezone: profile.timezone,
      model: profile.model,
      manufacturer: profile.manufacturer,
      appVersion: profile.appVersion,
      ip: profile.ip,
      language: place.language,
      countryCode: place.countryCode,
      sdkVersion: notifiableSDKVersion
    )
    let subscriber = try await api.saveSubscriber(write)
    let storage = await resolveStorage()
    let next = StoredSession(
      deviceId: session.deviceId,
      subscriberId: subscriber.id,
      pushToken: token?.token,
      anonymousId: subscriber.anonymousId
    )
    await saveSession(storage: storage, publicKey: configuration.publicKey, session: next)
    self.session = next
    commit(
      ready: true,
      permission: savedPermission,
      subscriber: subscriber,
      error: .some(nil)
    )
    logger.info(
      "Subscriber saved",
      context: [
        "subscriberId": subscriber.id,
        "permission": savedPermission.rawValue,
      ]
    )
  }

  private func currentPermission() async -> PermissionStatus {
    guard let push = configuration.push else {
      return .notDetermined
    }

    return await push.permissionStatus()
  }

  private func tokenFor(
    _ permission: PermissionStatus,
    requireToken: Bool = false
  ) async throws -> (token: String, provider: PushProvider)? {
    guard permission == .granted else {
      return nil
    }

    guard let push = configuration.push else {
      throw NotifiableError(
        code: .missingToken,
        message: "Push permission is granted, but no push port is configured."
      )
    }

    let token = (await push.token())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if token.isEmpty {
      if push.allowMissingToken && !requireToken {
        return nil
      }

      let detail = await push.registrationError()
      throw NotifiableError(
        code: .missingToken,
        message: detail
          ?? "Push permission is granted, but no device token was returned."
      )
    }

    return (token, push.provider)
  }

  private func saveDeepLinks() async throws {
    guard let links = configuration.deepLinks else {
      return
    }

    let saved = try await api.saveDeepLinks(links)
    commit(deepLinks: saved)
    logger.info("Deep links saved", context: ["count": String(saved.count)])
  }

  private func resolveStorage() async -> any KeyValueStore {
    storage
  }

  private func requireSession() throws -> StoredSession {
    guard let session else {
      throw NotifiableError(
        code: .subscriberNotFound,
        message: "The subscriber is not registered yet."
      )
    }

    return session
  }

  private func requireSubscriberId() throws -> String {
    guard let subscriberId = try requireSession().subscriberId else {
      throw NotifiableError(
        code: .subscriberNotFound,
        message: "The subscriber is not registered yet."
      )
    }

    return subscriberId
  }

  private func guardRun<T>(_ task: () async throws -> T) async throws -> T {
    do {
      return try await task()
    } catch {
      report(error)
      let wrapped = asNotifiableError(error)
      commit(error: wrapped)
      throw wrapped
    }
  }

  private func capture<T>(_ task: () async throws -> T) async throws -> T {
    do {
      return try await task()
    } catch {
      report(error)
      throw asNotifiableError(error)
    }
  }

  private func diagnosticsOpen() -> Bool {
    snapshot.clientConfig?.environment == .development && diagnosticsChoice != .disabled
  }

  private func report(_ error: Error) {
    guard diagnosticsOpen() else {
      return
    }

    let described = describeCrash(error, symbols: Thread.callStackSymbols)
    let fingerprint = crashFingerprint(
      type: described.type,
      message: described.message,
      frames: described.frames
    )

    if diagnosticSeen.contains(fingerprint) {
      return
    }

    diagnosticSeen.insert(fingerprint)
    diagnosticQueue.append(
      PendingDiagnostic(
        id: ULID.create(),
        occurredAt: ISO8601DateFormatter().string(from: Date()),
        type: described.type,
        message: described.message,
        frames: described.frames,
        subscriberId: diagnosticSubscriberId(session?.subscriberId)
      )
    )

    if diagnosticQueue.count > 20 {
      diagnosticQueue.removeFirst()
    }

    Task { @MainActor in
      await self.flushDiagnostics()
    }
  }

  private func flushDiagnostics() async {
    if diagnosticFlushing || diagnosticQueue.isEmpty {
      return
    }

    if !diagnosticsOpen() {
      diagnosticQueue = []
      return
    }

    diagnosticFlushing = true
    let batch = Array(diagnosticQueue.prefix(20))
    diagnosticQueue.removeFirst(min(20, diagnosticQueue.count))

    do {
      let profile = await device.profile()

      if !diagnosticsOpen() {
        diagnosticFlushing = false
        return
      }

      _ = try await api.reportDiagnostics(
        batch.map { item in
          DiagnosticCrash(
            id: item.id,
            sdkVersion: notifiableSDKVersion,
            platform: profile.platform,
            occurredAt: item.occurredAt,
            errorType: item.type,
            errorMessage: item.message,
            frames: item.frames,
            subscriberId: item.subscriberId
          )
        }
      )
    } catch {
      diagnosticFlushing = false
      return
    }

    diagnosticFlushing = false

    if !diagnosticQueue.isEmpty {
      await flushDiagnostics()
    }
  }

  private func commit(
    ready: Bool? = nil,
    permission: PermissionStatus? = nil,
    subscriber: Subscriber? = nil,
    clientConfig: DeliveryConfig? = nil,
    devIndicator: DevIndicatorChoice? = nil,
    diagnostics: DiagnosticsChoice? = nil,
    deepLinks: [DeepLink]? = nil,
    error: NotifiableError?? = nil
  ) {
    var next = snapshot

    if let ready {
      next.ready = ready
    }

    if let permission {
      next.permission = permission
    }

    if let subscriber {
      next.subscriber = subscriber
    }

    if let clientConfig {
      next.clientConfig = clientConfig
    }

    if let devIndicator {
      next.devIndicator = devIndicator
    }

    if let diagnostics {
      next.diagnostics = diagnostics
    }

    if let deepLinks {
      next.deepLinks = deepLinks
    }

    if let error {
      next.error = error
    }

    snapshot = next
  }
}

private struct PendingDiagnostic {
  var id: String
  var occurredAt: String
  var type: String
  var message: String
  var frames: [StackFrame]
  var subscriberId: String?
}

private func installLinkedApplePlatform() {
  let name = "NotifiableApplePlatform"
  guard let cls = NSClassFromString(name) as? NSObject.Type else {
    return
  }

  let selector = NSSelectorFromString("installApplePlatform")

  guard cls.responds(to: selector) else {
    return
  }

  cls.perform(selector)
}

private func identityFrom(_ input: IdentifyInput) throws -> SubscriberIdentity {
  var identity = SubscriberIdentity()

  if let email = input.email {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      throw NotifiableError(code: .invalidConfig, message: "email cannot be blank.")
    }

    identity.email = trimmed
  }

  if let externalId = input.externalId {
    let trimmed = externalId.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      throw NotifiableError(code: .invalidConfig, message: "externalId cannot be blank.")
    }

    identity.externalId = trimmed
  }

  if input.includesFirstName {
    identity.firstName = input.firstName
    identity.includesFirstName = true
  }

  if input.includesLastName {
    identity.lastName = input.lastName
    identity.includesLastName = true
  }

  if identity.email == nil && identity.externalId == nil && !identity.includesFirstName
    && !identity.includesLastName
  {
    throw NotifiableError(
      code: .invalidConfig,
      message: "identify requires an email, externalId, firstName, or lastName."
    )
  }

  if identity.email != nil || identity.externalId != nil {
    identity.anonymousId = .some(nil)
  }

  return identity
}
