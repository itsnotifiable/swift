import Foundation

struct SdkAPI {
  var http: HTTPClient

  func getClientConfig() async throws -> DeliveryConfig {
    let data = try await http.request(method: "GET", path: "/v1/sdk/client-config")
    return try parseDeliveryConfig(data)
  }

  func saveSubscriber(_ write: SubscriberWrite) async throws -> Subscriber {
    let data = try await http.request(
      method: "POST",
      path: "/v1/sdk/subscribers",
      body: subscriberBody(write)
    )
    return try parseSubscriber(data)
  }

  func updateSubscriber(subscriberId: String, identity: SubscriberIdentity) async throws -> Subscriber {
    let data = try await http.request(
      method: "PATCH",
      path: "/v1/sdk/subscribers/\(pathComponent(subscriberId))",
      body: identityBody(identity)
    )
    return try parseSubscriber(data)
  }

  func listNotifications(subscriberId: String, query: InboxQuery?) async throws -> InboxPage {
    let data = try await http.request(
      method: "GET",
      path: inboxPath(subscriberId, query)
    )
    return try parseInboxPage(data)
  }

  func getNotification(subscriberId: String, notificationId: String) async throws -> SubscriberNotification {
    let data = try await http.request(
      method: "GET",
      path: "/v1/sdk/subscribers/\(pathComponent(subscriberId))/notifications/\(pathComponent(notificationId))"
    )

    guard let notification = parseNotification(data) else {
      throw NotifiableError(code: .network, message: "The notification response was invalid.")
    }

    return notification
  }

  func openNotification(subscriberId: String, notificationId: String) async throws {
    _ = try await http.request(
      method: "POST",
      path: "/v1/sdk/subscribers/\(pathComponent(subscriberId))/notifications/\(pathComponent(notificationId))/open"
    )
  }

  func clickDelivery(deliveryId: String) async throws {
    _ = try await http.request(
      method: "POST",
      path: "/v1/sdk/deliveries/\(pathComponent(deliveryId))/click"
    )
  }

  func trackEvent(
    subscriberId: String,
    name: String,
    properties: [String: EventProperty]?
  ) async throws -> RecordedEvent {
    var body: [String: Any] = [
      "name": name,
      "subscriber_id": subscriberId,
    ]

    if let properties {
      body["properties"] = properties.mapValues(propertyValue)
    }

    let data = try await http.request(method: "POST", path: "/v1/sdk/events", body: body)
    return try parseRecordedEvent(data)
  }

  func saveDeepLinks(_ links: [DeepLink]) async throws -> [DeepLink] {
    let data = try await http.request(
      method: "POST",
      path: "/v1/sdk/deep-links",
      body: [
        "links": links.map { ["path": $0.path, "label": $0.label] },
      ]
    )
    return try parseDeepLinks(data)
  }

  func reportDiagnostics(_ items: [DiagnosticCrash]) async throws -> Int {
    let data = try await http.request(
      method: "POST",
      path: "/v1/sdk/diagnostics",
      body: [
        "items": items.map(diagnosticItem),
      ]
    )
    return try parseAccepted(data)
  }
}

func subscriberBody(_ write: SubscriberWrite) -> [String: Any] {
  var body: [String: Any] = [
    "device_id": write.deviceId,
    "platform": write.platform.rawValue,
    "sdk": notifiableSDKName,
    "permission": write.permission.rawValue,
  ]

  assign(&body, "provider", write.provider?.rawValue)
  assign(&body, "token", write.token)
  assign(&body, "anonymous_id", write.anonymousId)

  if write.prompted == true {
    body["prompted"] = true
  }

  assign(&body, "os_version", write.osVersion)
  assign(&body, "locale", write.locale)
  assign(&body, "timezone", write.timezone)
  assign(&body, "device_model", write.model)
  assign(&body, "device_manufacturer", write.manufacturer)
  assign(&body, "device_ip", write.ip)
  assign(&body, "app_version", write.appVersion)
  assign(&body, "sdk_version", write.sdkVersion)
  assign(&body, "language", write.language)
  assign(&body, "country_code", write.countryCode)
  return body
}

func identityBody(_ identity: SubscriberIdentity) -> [String: Any] {
  var body: [String: Any] = [:]
  assign(&body, "email", identity.email)
  assign(&body, "external_id", identity.externalId)

  if identity.includesFirstName {
    body["first_name"] = identity.firstName ?? NSNull()
  }

  if identity.includesLastName {
    body["last_name"] = identity.lastName ?? NSNull()
  }

  if let anonymousId = identity.anonymousId {
    body["anonymous_id"] = anonymousId ?? NSNull()
  }

  return body
}

private func assign(_ body: inout [String: Any], _ key: String, _ value: String?) {
  if let value {
    body[key] = value
  }
}

private func propertyValue(_ property: EventProperty) -> Any {
  switch property {
  case let .string(value):
    return value
  case let .number(value):
    return value
  case let .bool(value):
    return value
  case .null:
    return NSNull()
  }
}

private func diagnosticItem(_ item: DiagnosticCrash) -> [String: Any] {
  var body: [String: Any] = [
    "id": item.id,
    "kind": item.kind,
    "sdk": item.sdk,
    "sdk_version": item.sdkVersion,
    "platform": item.platform.rawValue,
    "occurred_at": item.occurredAt,
    "error": [
      "type": item.errorType,
      "message": item.errorMessage,
      "frames": item.frames.map {
        [
          "function": $0.function,
          "file": $0.file,
          "line": $0.line,
        ]
      },
    ],
  ]

  if let subscriberId = item.subscriberId {
    body["subscriber_id"] = subscriberId
  }

  return body
}

private func pathComponent(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}

private func inboxPath(_ subscriberId: String, _ query: InboxQuery?) -> String {
  var path = "/v1/sdk/subscribers/\(pathComponent(subscriberId))/notifications"
  var params: [String] = []

  if let page = query?.page {
    params.append("page=\(page)")
  }

  if let opened = query?.opened {
    params.append("opened=\(opened ? "true" : "false")")
  }

  if !params.isEmpty {
    path += "?\(params.joined(separator: "&"))"
  }

  return path
}

private let emptyDeliveryConfig = DeliveryConfig(
  environment: nil,
  app: nil,
  android: nil,
  ios: nil,
  web: nil
)

private func parseDeliveryConfig(_ data: JSONValue?) throws -> DeliveryConfig {
  if case let .array(items) = data {
    if items.isEmpty {
      return emptyDeliveryConfig
    }

    throw invalidClientConfig()
  }

  guard let fields = data?.object else {
    throw invalidClientConfig()
  }

  return DeliveryConfig(
    environment: clientEnvironment(fields["environment"]),
    app: parseClientApp(fields["app"]),
    android: recordOrNil(fields["android"]),
    ios: recordOrNil(fields["ios"]),
    web: recordOrNil(fields["web"])
  )
}

private func clientEnvironment(_ value: JSONValue?) -> ClientEnvironment? {
  guard case let .string(raw) = value else {
    return nil
  }

  return ClientEnvironment(rawValue: raw)
}

private func parseClientApp(_ value: JSONValue?) -> ClientApp? {
  guard let fields = value?.object else {
    return nil
  }

  return ClientApp(
    name: textOrNil(fields["name"]),
    description: textOrNil(fields["description"]),
    icon: textOrNil(fields["icon"])
  )
}

private func textOrNil(_ value: JSONValue?) -> String? {
  guard case let .string(text) = value, !text.isEmpty else {
    return nil
  }

  return text
}

private func invalidClientConfig() -> NotifiableError {
  NotifiableError(code: .network, message: "The client configuration response was invalid.")
}

private func parseSubscriber(_ data: JSONValue?) throws -> Subscriber {
  guard let fields = data?.object,
    case let .string(id) = fields["id"],
    case let .string(environment) = fields["environment"],
    case let .string(platformRaw) = fields["platform"],
    let platform = DevicePlatform(rawValue: platformRaw),
    case let .string(permissionRaw) = fields["permission"],
    let permission = PermissionStatus(rawValue: permissionRaw),
    case let .bool(promptPermission) = fields["prompt_permission"]
  else {
    throw NotifiableError(code: .network, message: "The subscriber response was invalid.")
  }

  let provider: PushProvider?

  if fields["provider"] == nil || fields["provider"] == .null {
    provider = nil
  } else if case let .string(raw) = fields["provider"], let parsed = PushProvider(rawValue: raw) {
    provider = parsed
  } else {
    throw NotifiableError(code: .network, message: "The subscriber response was invalid.")
  }

  return Subscriber(
    id: id,
    environment: environment,
    platform: platform,
    permission: permission,
    sdk: textOrNil(fields["sdk"]),
    provider: provider,
    deviceId: textOrNil(fields["device_id"]),
    externalId: textOrNil(fields["external_id"]),
    anonymousId: textOrNil(fields["anonymous_id"]),
    promptPermission: promptPermission
  )
}

private func recordOrNil(_ value: JSONValue?) -> [String: JSONValue]? {
  value?.object
}

private func parseAccepted(_ data: JSONValue?) throws -> Int {
  guard let fields = data?.object, case let .number(accepted) = fields["accepted"],
    accepted.rounded() == accepted
  else {
    throw NotifiableError(code: .network, message: "The diagnostics response was invalid.")
  }

  return Int(accepted)
}

private func parseRecordedEvent(_ data: JSONValue?) throws -> RecordedEvent {
  guard let fields = data?.object,
    case let .string(id) = fields["id"],
    !id.isEmpty,
    case let .string(name) = fields["name"],
    case let .string(subscriberId) = fields["subscriber_id"]
  else {
    throw NotifiableError(code: .network, message: "The event response was invalid.")
  }

  return RecordedEvent(id: id, name: name, subscriberId: subscriberId)
}

private func parseDeepLinks(_ data: JSONValue?) throws -> [DeepLink] {
  guard let fields = data?.object, case let .array(links) = fields["links"] else {
    throw NotifiableError(code: .network, message: "The deep link response was invalid.")
  }

  return links.compactMap { entry in
    guard let fields = entry.object,
      case let .string(path) = fields["path"],
      !path.isEmpty,
      case let .string(label) = fields["label"],
      !label.isEmpty
    else {
      return nil
    }

    return DeepLink(path: path, label: label)
  }
}

private func parseInboxPage(_ data: JSONValue?) throws -> InboxPage {
  guard let fields = data?.object,
    case let .array(notifications) = fields["notifications"],
    case let .number(page) = fields["page"],
    case let .number(perPage) = fields["per_page"],
    case let .number(total) = fields["total"]
  else {
    throw NotifiableError(code: .network, message: "The notification list was invalid.")
  }

  return InboxPage(
    notifications: notifications.compactMap(parseNotification),
    page: Int(page),
    perPage: Int(perPage),
    total: Int(total)
  )
}

private func parseNotification(_ value: JSONValue?) -> SubscriberNotification? {
  guard let fields = value?.object,
    case let .string(id) = fields["id"],
    !id.isEmpty,
    case let .string(title) = fields["title"],
    case let .string(body) = fields["body"],
    case let .bool(opened) = fields["opened"],
    case let .string(createdAt) = fields["created_at"]
  else {
    return nil
  }

  let alert: Bool

  if case let .bool(value) = fields["alert"] {
    alert = value
  } else {
    alert = true
  }

  return SubscriberNotification(
    id: id,
    title: title,
    body: body,
    url: textOrNil(fields["url"]),
    imageUrl: textOrNil(fields["image_url"]),
    data: recordOrNil(fields["data"]),
    alert: alert,
    status: textOrNil(fields["status"]),
    opened: opened,
    openedAt: textOrNil(fields["opened_at"]),
    createdAt: createdAt,
    deliveryId: textOrNil(fields["delivery_id"])
  )
}
