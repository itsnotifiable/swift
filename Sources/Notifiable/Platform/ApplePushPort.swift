#if os(iOS)
import Foundation
import NotifiableCore
import UIKit
import UserNotifications

public final class ApplePushPort: PushPort, @unchecked Sendable {
  public let provider: PushProvider = .apns
  public let allowMissingToken = true

  public init() {}

  public func permissionStatus() async -> PermissionStatus {
    let settings = await notificationSettings()
    return map(settings.authorizationStatus)
  }

  public func requestPermission() async -> PermissionStatus {
    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false

    if granted {
      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }

    return await permissionStatus()
  }

  public func token() async -> String? {
    await PushTokenStore.shared.current()
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
