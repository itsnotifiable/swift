import XCTest
@testable import NotifiableCore

final class NotifiableClientTests: XCTestCase {
  @MainActor
  func testBlankKeyThrowsBeforeARequest() {
    let transport = StubTransport { _ in success([:]) }

    XCTAssertThrowsError(
      try NotifiableClient(
        publicKey: "  ",
        device: FakeDevice(),
        transport: transport
      )
    ) { error in
      XCTAssertEqual((error as? NotifiableError)?.code, .invalidConfig)
    }

    XCTAssertTrue(transport.recorded().isEmpty)
  }

  @MainActor
  func testEnvelopeMapsApiErrors() async throws {
    let transport = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "development"))
      }

      if call.url.contains("subscribers") {
        return success(subscriber(prompt: false))
      }

      return [
        "status": "error",
        "code": "VALIDATION_FAILED",
        "message": "Invalid",
        "error": [
          "details": [
            ["message": "Email is invalid."],
            ["message": "Try another."],
          ],
        ],
      ]
    }
    let client = try makeClient(transport: transport, push: nil)
    try await client.start()
    let error = try await XCTUnwrapError {
      try await client.track(name: "opened")
    }

    XCTAssertEqual(error.code, .validationFailed)
    XCTAssertEqual(error.message, "Email is invalid. Try another.")
  }

  @MainActor
  func testSubscriberBodyAndPromptThenSave() async throws {
    let transport = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "development"))
      }

      if call.url.contains("deep-links") {
        return success(["links": [["path": "/orders", "label": "Orders"]]])
      }

      let prompted = call.body["prompted"] as? Bool == true
      return success(
        subscriber(prompt: !prompted, permission: prompted ? "granted" : "not_determined")
      )
    }
    let push = FakePush()
    push.deviceToken = "abc123"
    let storage = MemoryStorage()
    let client = try makeClient(
      transport: transport,
      push: push,
      storage: storage,
      deepLinks: [DeepLink(path: "/orders", label: "Orders")]
    )

    try await client.start()

    let posts = transport.recorded().filter { $0.method == "POST" && $0.url.contains("/subscribers") }
    XCTAssertEqual(posts.count, 2)
    let first = posts[0].body
    XCTAssertEqual(first["sdk"] as? String, "swift")
    XCTAssertEqual(first["platform"] as? String, "ios")
    XCTAssertEqual(first["permission"] as? String, "not_determined")
    XCTAssertNil(first["provider"])
    XCTAssertNil(first["token"])
    XCTAssertNil(first["prompted"])
    XCTAssertEqual(first["language"] as? String, "en")
    XCTAssertEqual(first["country_code"] as? String, "MA")
    XCTAssertEqual(first["sdk_version"] as? String, notifiableSDKVersion)
    XCTAssertNotNil(first["anonymous_id"] as? String)
    XCTAssertEqual(posts[0].key, "ntf_pub_test")

    let second = posts[1].body
    XCTAssertEqual(second["prompted"] as? Bool, true)
    XCTAssertEqual(second["permission"] as? String, "granted")
    XCTAssertEqual(second["provider"] as? String, "apns")
    XCTAssertEqual(second["token"] as? String, "abc123")
    XCTAssertNil(second["anonymous_id"])
    XCTAssertEqual(push.requests, 1)
    XCTAssertEqual(client.snapshot.permission, .granted)
    XCTAssertEqual(client.snapshot.deepLinks, [DeepLink(path: "/orders", label: "Orders")])

    let raw = await storage.getItem(sessionKey("ntf_pub_test"))
    let saved = try XCTUnwrap(raw)
    XCTAssertTrue(saved.contains(posts[0].body["device_id"] as? String ?? "missing"))

    let again = try makeClient(transport: transport, push: push, storage: storage)
    try await again.start()
    let later = transport.recorded().filter { $0.method == "POST" && $0.url.contains("/subscribers") }
    XCTAssertEqual(later.last?.body["device_id"] as? String, first["device_id"] as? String)
  }

  @MainActor
  func testGrantedWithoutTokenSavesNotDetermined() async throws {
    let transport = countingSubscriberTransport()
    let push = FakePush()
    push.status = .granted
    push.deviceToken = "   "
    let client = try makeClient(transport: transport, push: push)

    try await client.start()

    let body = try XCTUnwrap(transport.recorded().first { $0.method == "POST" }?.body)
    XCTAssertEqual(body["permission"] as? String, "not_determined")
    XCTAssertNil(body["provider"])
    XCTAssertNil(body["token"])
    XCTAssertEqual(client.snapshot.permission, .notDetermined)
  }

  @MainActor
  func testIdentifyClearsAnonymousId() async throws {
    let transport = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "production"))
      }

      if call.method == "PATCH" {
        var saved = subscriber(prompt: false, permission: "not_determined")
        saved["external_id"] = "user_123"
        return success(saved)
      }

      return success(subscriber(prompt: false))
    }
    let client = try makeClient(transport: transport, push: nil)
    try await client.start()
    let identified = try await client.identify(email: "ada@example.com", externalId: "user_123")
    let patch = try XCTUnwrap(transport.recorded().first { $0.method == "PATCH" })

    XCTAssertEqual(patch.body["email"] as? String, "ada@example.com")
    XCTAssertEqual(patch.body["external_id"] as? String, "user_123")
    XCTAssertTrue(patch.body["anonymous_id"] is NSNull)
    XCTAssertEqual(identified.externalId, "user_123")
    XCTAssertFalse(transport.recorded().contains { $0.url.contains("diagnostics") })
  }

  @MainActor
  func testInboxParsing() async throws {
    let transport = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "production"))
      }

      if call.method == "POST" {
        return success(subscriber(prompt: false))
      }

      XCTAssertTrue(call.url.contains("page=1"))
      XCTAssertTrue(call.url.contains("opened=false"))
      return success([
        "notifications": [
          [
            "id": "note_1",
            "title": "Hello",
            "body": "World",
            "url": "/orders?opt=delivery_1",
            "opened": false,
            "created_at": "2026-10-17T22:00:00Z",
            "alert": true,
            "delivery_id": "",
          ],
          ["id": ""],
        ],
        "page": 1,
        "per_page": 20,
        "total": 1,
      ])
    }
    let client = try makeClient(transport: transport, push: nil)
    try await client.start()
    let page = try await client.inbox(query: InboxQuery(page: 1, opened: false))

    XCTAssertEqual(page.perPage, 20)
    XCTAssertEqual(page.total, 1)
    XCTAssertEqual(page.notifications.count, 1)
    XCTAssertEqual(page.notifications[0].title, "Hello")
    XCTAssertEqual(notificationDeliveryId(page.notifications[0]), "delivery_1")
  }

  @MainActor
  func testDiagnosticsOncePerFingerprintAndNotInProduction() async throws {
    let transport = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "development"))
      }

      if call.url.contains("diagnostics") {
        return success(["accepted": 1])
      }

      if call.url.contains("notifications") {
        return [
          "status": "error",
          "code": "RATE_LIMIT_EXCEEDED",
          "message": "Slow down",
        ]
      }

      return success(subscriber(prompt: false))
    }
    let client = try makeClient(transport: transport, push: nil)
    try await client.start()

    do {
      _ = try await client.inbox()
      XCTFail("Expected the inbox to fail")
    } catch let error as NotifiableError {
      XCTAssertEqual(error.code, .rateLimited)
    }

    do {
      _ = try await client.inbox()
    } catch {}

    try await waitUntil {
      transport.recorded().filter { $0.url.contains("diagnostics") }.count == 1
    }

    let report = try XCTUnwrap(transport.recorded().first { $0.url.contains("diagnostics") })
    let items = try XCTUnwrap(report.body["items"] as? [[String: Any]])
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0]["sdk"] as? String, "swift")
    XCTAssertEqual(items[0]["platform"] as? String, "ios")

    await client.setDiagnostics(enabled: false)
    let before = transport.recorded().filter { $0.url.contains("diagnostics") }.count

    do {
      _ = try await client.track(name: "later")
    } catch {}

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(transport.recorded().filter { $0.url.contains("diagnostics") }.count, before)

    let production = StubTransport { call in
      if call.url.contains("client-config") {
        return success(clientConfig(environment: "production"))
      }

      if call.url.contains("diagnostics") {
        return success(["accepted": 1])
      }

      if call.url.contains("notifications") {
        return [
          "status": "error",
          "code": "RATE_LIMIT_EXCEEDED",
          "message": "Slow down",
        ]
      }

      return success(subscriber(prompt: false))
    }
    let productionClient = try makeClient(transport: production, push: nil)
    try await productionClient.start()

    do {
      _ = try await productionClient.inbox()
    } catch {}

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(production.recorded().filter { $0.url.contains("diagnostics") }.isEmpty)
  }

  func testFreshNotificationsAndPackageCheck() {
    let now = Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970 * 1000
    let recent = notification(id: "recent", createdAt: iso(now - 1_000), opened: false, alert: true)
    let stale = notification(id: "stale", createdAt: iso(now - 9_000), opened: false, alert: true)
    let opened = notification(id: "opened", createdAt: iso(now - 1_000), opened: true, alert: true)
    let silent = notification(id: "silent", createdAt: iso(now - 1_000), opened: false, alert: false)
    let soon = notification(id: "soon", createdAt: iso(now + 1_000), opened: false, alert: true)
    let fresh = selectFreshNotifications(
      [recent, stale, opened, silent, soon],
      nowMs: now,
      seen: ["recent"]
    )

    XCTAssertEqual(fresh.map(\.id), ["soon"])
    XCTAssertEqual(packageCheck(configured: "app", applicationId: "app"), .match)
    XCTAssertEqual(packageCheck(configured: "other", applicationId: "app"), .mismatch)
    XCTAssertEqual(packageCheck(configured: nil, applicationId: "app"), .mismatch)
    XCTAssertNil(packageCheck(configured: "app", applicationId: nil))
    XCTAssertNil(packageCheck(configured: "app", applicationId: ""))
    XCTAssertEqual(localeParts("en-MA").language, "en")
    XCTAssertEqual(localeParts("en-MA").countryCode, "MA")
    XCTAssertEqual(localeParts("en_MA").countryCode, "MA")
    XCTAssertNil(deviceAddress("127.0.0.1"))
    XCTAssertNil(deviceAddress("0.0.0.0"))
    XCTAssertEqual(deviceAddress("10.0.0.8"), "10.0.0.8")
    XCTAssertEqual(crashFingerprint(type: "Error", message: "Nope", frames: []), "Error|Nope|")
  }
}

@MainActor
private func makeClient(
  transport: StubTransport,
  push: FakePush?,
  storage: MemoryStorage = MemoryStorage(),
  deepLinks: [DeepLink]? = nil
) throws -> NotifiableClient {
  try NotifiableClient(
    publicKey: "ntf_pub_test",
    push: push,
    storage: storage,
    device: FakeDevice(),
    deepLinks: deepLinks,
    transport: transport
  )
}

private func countingSubscriberTransport() -> StubTransport {
  StubTransport { call in
    if call.url.contains("client-config") {
      return success(clientConfig(environment: "production"))
    }

    return success(subscriber(prompt: false))
  }
}

private func success(_ data: Any) -> [String: Any] {
  ["status": "success", "data": data]
}

private func clientConfig(environment: String) -> [String: Any] {
  [
    "environment": environment,
    "app": ["name": "Example", "description": "Demo", "icon": "https://notifiable.sh/favicon.png"],
    "ios": ["bundle_id": "sh.notifiable.demo"],
  ]
}

private func subscriber(prompt: Bool, permission: String = "not_determined") -> [String: Any] {
  [
    "id": "11111111-1111-4111-8111-111111111111",
    "environment": "development",
    "platform": "ios",
    "permission": permission,
    "prompt_permission": prompt,
    "sdk": "swift",
    "device_id": "device",
  ]
}

private func notification(
  id: String,
  createdAt: String,
  opened: Bool,
  alert: Bool
) -> SubscriberNotification {
  SubscriberNotification(
    id: id,
    title: id,
    body: "",
    url: nil,
    imageUrl: nil,
    data: nil,
    alert: alert,
    status: nil,
    opened: opened,
    openedAt: nil,
    createdAt: createdAt,
    deliveryId: nil
  )
}

private func iso(_ milliseconds: TimeInterval) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
}

private func waitUntil(
  attempts: Int = 50,
  condition: @MainActor () -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() {
      return
    }

    try await Task.sleep(nanoseconds: 20_000_000)
  }

  XCTFail("Timed out waiting for a condition")
}

private final class StubTransport: HTTPSending, @unchecked Sendable {
  struct Call {
    var method: String
    var url: String
    var key: String?
    var body: [String: Any]
  }

  private let lock = NSLock()
  private var calls: [Call] = []
  private let handler: (Call) -> [String: Any]

  init(handler: @escaping (Call) -> [String: Any]) {
    self.handler = handler
  }

  func send(_ request: URLRequest) async throws -> HTTPResult {
    let body = request.httpBody.flatMap {
      try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    } ?? [:]
    let call = Call(
      method: request.httpMethod ?? "",
      url: request.url?.absoluteString ?? "",
      key: request.value(forHTTPHeaderField: "X-Notifiable-Key"),
      body: body
    )
    lock.lock()
    calls.append(call)
    lock.unlock()
    let envelope = handler(call)
    return HTTPResult(
      statusCode: 200,
      body: try JSONSerialization.data(withJSONObject: envelope)
    )
  }

  func recorded() -> [Call] {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }
}

private final class FakePush: PushPort, @unchecked Sendable {
  let provider: PushProvider = .apns
  let allowMissingToken = true
  var status: PermissionStatus = .notDetermined
  var deviceToken: String?
  var requests = 0

  func permissionStatus() async -> PermissionStatus {
    status
  }

  func requestPermission() async -> PermissionStatus {
    requests += 1
    status = .granted
    return status
  }

  func token() async -> String? {
    deviceToken
  }
}

private struct FakeDevice: DevicePort {
  func profile() async -> DeviceProfile {
    DeviceProfile(
      platform: .ios,
      locale: "en-MA",
      timezone: "Africa/Casablanca",
      model: "iPhone",
      manufacturer: "Apple",
      appVersion: "1.0",
      ip: "10.0.0.8"
    )
  }

  func applicationId() async -> String? {
    "sh.notifiable.example"
  }

  func copy(_ value: String) {}
}

private extension XCTestCase {
  func XCTUnwrapError(
    _ body: () async throws -> some Any
  ) async throws -> NotifiableError {
    do {
      _ = try await body()
      XCTFail("Expected an error")
      throw NotifiableError(code: .network, message: "Expected an error")
    } catch let error as NotifiableError {
      return error
    } catch {
      XCTFail("Expected NotifiableError")
      throw NotifiableError(code: .network, message: "Expected NotifiableError")
    }
  }
}
