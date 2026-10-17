#if os(iOS)
import Foundation
import NotifiableCore
import UIKit

@objc(NotifiableApplePlatform)
public final class NotifiableApplePlatform: NSObject {
  @objc public static func installApplePlatform() {
    installNotifiableApplePlatform()
  }
}

#endif
