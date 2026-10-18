#if os(iOS)
import Foundation
import NotifiableCore
import os
import UIKit

private let pushLog = Logger(subsystem: "sh.notifiable.swift", category: "push")

public final class NotifiableAppDelegate: NSObject, UIApplicationDelegate {
  public override init() {
    super.init()
    installNotifiableApplePlatform()
  }

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    true
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    pushLog.info("APNs device token received (\(deviceToken.count, privacy: .public) bytes)")
    PushTokenStore.shared.set(deviceToken: deviceToken)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pushLog.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    PushTokenStore.shared.fail(error.localizedDescription)
  }
}

public extension NotifiableClient {
  static func didRegisterForRemoteNotifications(deviceToken: Data) {
    PushTokenStore.shared.set(deviceToken: deviceToken)
  }

  static func didFailToRegisterForRemoteNotifications(_ message: String = "APNs registration failed.") {
    PushTokenStore.shared.fail(message)
  }
}

func installNotifiableApplePlatform() {
  NotifiablePlatformRegistry.register(
    push: { ApplePushPort() },
    device: { AppleDevicePort() }
  )
}

@_cdecl("NotifiableInstallApplePlatform")
public func NotifiableInstallApplePlatform() {
  installNotifiableApplePlatform()
}

#endif
