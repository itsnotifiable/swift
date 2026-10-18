import Foundation

public final class PushTokenStore: @unchecked Sendable {
  public static let shared = PushTokenStore()

  private let lock = NSLock()
  private var token: String?
  private var failed = false
  private var failure: String?

  public func set(deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lock.lock()
    token = hex
    failed = false
    lock.unlock()
  }

  public func fail(_ message: String) {
    lock.lock()
    failed = true
    failure = message
    lock.unlock()
  }

  public func prepareForRegistration() {
    lock.lock()
    failed = false
    failure = nil
    lock.unlock()
  }

  public func failureMessage() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return failure
  }

  public func current(timeout: TimeInterval = 10) async -> String? {
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
