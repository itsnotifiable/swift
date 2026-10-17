#if os(iOS)
import Foundation
import NotifiableCore
import UIKit

public final class NotifiableAppDelegate: NSObject, UIApplicationDelegate {
  public override init() {
    super.init()
    installNotifiableApplePlatform()
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushTokenStore.shared.set(deviceToken: deviceToken)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushTokenStore.shared.fail()
  }
}

public extension NotifiableClient {
  static func didRegisterForRemoteNotifications(deviceToken: Data) {
    PushTokenStore.shared.set(deviceToken: deviceToken)
  }

  static func didFailToRegisterForRemoteNotifications() {
    PushTokenStore.shared.fail()
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
