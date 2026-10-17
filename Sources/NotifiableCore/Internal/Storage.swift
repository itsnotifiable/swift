import Foundation
import Security

public func sessionKey(_ publicKey: String) -> String {
  "notifiable.session.\(publicKey)"
}

public func diagnosticsKey(_ publicKey: String) -> String {
  "notifiable.diagnostics.\(publicKey)"
}

public func devIndicatorKey(_ publicKey: String) -> String {
  "notifiable.dev-indicator.\(publicKey)"
}

func loadSession(storage: any KeyValueStore, publicKey: String) async -> StoredSession? {
  guard let raw = await storage.getItem(sessionKey(publicKey)),
    let data = raw.data(using: .utf8),
    let json = try? JSON.value(from: data),
    let fields = json.object,
    case let .string(deviceId) = fields["deviceId"],
    !deviceId.isEmpty
  else {
    return nil
  }

  return StoredSession(
    deviceId: deviceId,
    subscriberId: fields["subscriberId"]?.string,
    pushToken: fields["pushToken"]?.string,
    anonymousId: fields["anonymousId"]?.string
  )
}

func saveSession(storage: any KeyValueStore, publicKey: String, session: StoredSession) async {
  var fields: [String: Any] = [
    "deviceId": session.deviceId,
    "subscriberId": session.subscriberId ?? NSNull(),
    "pushToken": session.pushToken ?? NSNull(),
    "anonymousId": session.anonymousId ?? NSNull(),
  ]

  if session.subscriberId == nil {
    fields["subscriberId"] = NSNull()
  }

  guard let data = try? JSON.data(from: fields), let raw = String(data: data, encoding: .utf8) else {
    return
  }

  await storage.setItem(sessionKey(publicKey), value: raw)
}

func loadChoice<Choice: RawRepresentable>(
  storage: any KeyValueStore,
  key: String
) async -> Choice? where Choice.RawValue == String {
  guard let raw = await storage.getItem(key) else {
    return nil
  }

  return Choice(rawValue: raw)
}

func saveChoice(storage: any KeyValueStore, key: String, value: String) async {
  await storage.setItem(key, value: value)
}

public actor MemoryStorage: KeyValueStore {
  private var values: [String: String] = [:]

  public init() {}

  public func getItem(_ key: String) async -> String? {
    values[key]
  }

  public func setItem(_ key: String, value: String) async {
    values[key] = value
  }

  public func removeItem(_ key: String) async {
    values.removeValue(forKey: key)
  }
}

public final class UserDefaultsStorage: KeyValueStore, @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func getItem(_ key: String) async -> String? {
    defaults.string(forKey: key)
  }

  public func setItem(_ key: String, value: String) async {
    defaults.set(value, forKey: key)
  }

  public func removeItem(_ key: String) async {
    defaults.removeObject(forKey: key)
  }
}

enum ULID {
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

  static func create(time: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) -> String {
    encodeTime(time) + encodeRandom()
  }

  private static func encodeTime(_ time: UInt64) -> String {
    var value = time
    var chars: [Character] = []

    for _ in 0..<10 {
      chars.append(alphabet[Int(value % 32)])
      value /= 32
    }

    return String(chars.reversed())
  }

  private static func encodeRandom() -> String {
    var bytes = [UInt8](repeating: 0, count: 10)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    var buffer = 0
    var bits = 0
    var encoded = ""

    for byte in bytes {
      buffer = (buffer << 8) | Int(byte)
      bits += 8

      while bits >= 5 {
        bits -= 5
        encoded.append(alphabet[(buffer >> bits) & 31])
      }
    }

    return encoded
  }
}

func createId() -> String {
  UUID().uuidString.lowercased()
}

public enum NotifiablePlatformRegistry {
  private static let lock = NSLock()
  private static var pushFactory: (() -> any PushPort)?
  private static var deviceFactory: (() -> any DevicePort)?

  public static func register(
    push: @escaping () -> any PushPort,
    device: @escaping () -> any DevicePort
  ) {
    lock.lock()
    pushFactory = push
    deviceFactory = device
    lock.unlock()
  }

  static func makePush() -> (any PushPort)? {
    lock.lock()
    defer { lock.unlock() }
    return pushFactory?()
  }

  static func makeDevice() -> (any DevicePort)? {
    lock.lock()
    defer { lock.unlock() }
    return deviceFactory?()
  }
}
