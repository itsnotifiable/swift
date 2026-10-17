import Foundation

public final class PushTokenStore: @unchecked Sendable {
  public static let shared = PushTokenStore()

  private let lock = NSLock()
  private var token: String?
  private var failed = false

  public func set(deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lock.lock()
    token = hex
    failed = false
    lock.unlock()
  }

  public func fail() {
    lock.lock()
    failed = true
    lock.unlock()
  }

  public func current(timeout: TimeInterval = 2) async -> String? {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if let token = read() {
        return token
      }

      if didFail() {
        return nil
      }

      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    return read()
  }

  private func read() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return token
  }

  private func didFail() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return failed
  }
}
