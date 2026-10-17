import Foundation

public struct SubscriberNotification: Sendable, Equatable, Identifiable {
  public var id: String
  public var title: String
  public var body: String
  public var url: String?
  public var imageUrl: String?
  public var data: [String: JSONValue]?
  public var alert: Bool
  public var status: String?
  public var opened: Bool
  public var openedAt: String?
  public var createdAt: String
  public var deliveryId: String?

  public init(
    id: String,
    title: String,
    body: String,
    url: String?,
    imageUrl: String?,
    data: [String: JSONValue]?,
    alert: Bool,
    status: String?,
    opened: Bool,
    openedAt: String?,
    createdAt: String,
    deliveryId: String?
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.url = url
    self.imageUrl = imageUrl
    self.data = data
    self.alert = alert
    self.status = status
    self.opened = opened
    self.openedAt = openedAt
    self.createdAt = createdAt
    self.deliveryId = deliveryId
  }
}

public struct InboxQuery: Sendable, Equatable {
  public var page: Int?
  public var opened: Bool?

  public init(page: Int? = nil, opened: Bool? = nil) {
    self.page = page
    self.opened = opened
  }
}

public struct InboxPage: Sendable, Equatable {
  public var notifications: [SubscriberNotification]
  public var page: Int
  public var perPage: Int
  public var total: Int

  public init(
    notifications: [SubscriberNotification],
    page: Int,
    perPage: Int,
    total: Int
  ) {
    self.notifications = notifications
    self.page = page
    self.perPage = perPage
    self.total = total
  }
}

public func notificationDeliveryId(_ notification: SubscriberNotification) -> String? {
  if let deliveryId = notification.deliveryId, !deliveryId.isEmpty {
    return deliveryId
  }

  guard let url = notification.url, let components = URLComponents(string: url) else {
    if let url = notification.url,
      let components = URLComponents(string: "https://notifiable.invalid\(url.hasPrefix("/") ? "" : "/")\(url)")
    {
      return queryValue(components, name: "opt")
    }

    return nil
  }

  return queryValue(components, name: "opt")
}

private func queryValue(_ components: URLComponents, name: String) -> String? {
  let value = components.queryItems?.first(where: { $0.name == name })?.value
  guard let value, !value.isEmpty else {
    return nil
  }

  return value
}

public let devNotificationFreshMs: TimeInterval = 8_000
private let clockSkewMs: TimeInterval = 2_000

public func selectFreshNotifications(
  _ notifications: [SubscriberNotification],
  nowMs: TimeInterval,
  seen: Set<String>
) -> [SubscriberNotification] {
  notifications.filter { notification in
    if notification.opened || !notification.alert || seen.contains(notification.id) {
      return false
    }

    guard let created = parseTimestamp(notification.createdAt) else {
      return false
    }

    let age = nowMs - created
    return age >= -clockSkewMs && age <= devNotificationFreshMs
  }
}

private func parseTimestamp(_ value: String) -> TimeInterval? {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

  if let date = formatter.date(from: value) {
    return date.timeIntervalSince1970 * 1000
  }

  formatter.formatOptions = [.withInternetDateTime]

  if let date = formatter.date(from: value) {
    return date.timeIntervalSince1970 * 1000
  }

  return nil
}
