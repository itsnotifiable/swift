#if os(iOS)
import Foundation
import NotifiableCore
import os
import UIKit
import UserNotifications

private let pushLog = Logger(subsystem: "sh.notifiable.swift", category: "push")

public final class ApplePushPort: PushPort, @unchecked Sendable {
  public let provider: PushProvider = .apns
  public let allowMissingToken = true

  public init() {}

  public func permissionStatus() async -> PermissionStatus {
    let settings = await notificationSettings()
    return map(settings.authorizationStatus)
  }

  public func requestPermission() async -> PermissionStatus {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.main.async {
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .badge, .sound]
        ) { _, _ in
          continuation.resume()
        }
      }
    }

    let status = await permissionStatus()
    pushLog.info("Permission request finished with \(status.rawValue, privacy: .public)")

    if status == .granted {
      await registerForRemoteNotifications()
    }

    return status
  }

  public func token() async -> String? {
    if await permissionStatus() == .granted {
      await registerForRemoteNotifications()
    }

    return await PushTokenStore.shared.current(timeout: 10)
  }

  public func registrationError() async -> String? {
    PushTokenStore.shared.failureMessage()
  }

  private func registerForRemoteNotifications() async {
      await MainActor.run {
      PushTokenStore.shared.prepareForRegistration()
      pushLog.info("Registering for remote notifications")
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  private func notificationSettings() async -> UNNotificationSettings {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        continuation.resume(returning: settings)
      }
    }
  }

  private func map(_ status: UNAuthorizationStatus) -> PermissionStatus {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return .granted
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .notDetermined
    }
  }
}

#endif
