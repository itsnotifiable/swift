#if os(iOS)
import Foundation
import NotifiableCore
import ObjectiveC
import UIKit

enum DevelopmentShortcut {
  static var onShow: (() -> Void)?
  private static var enabled = false
  private static var installed = false

  static func setEnabled(_ value: Bool) {
    enabled = value

    if value {
      install()
    }
  }

  fileprivate static var isEnabled: Bool {
    enabled
  }

  private static func install() {
    guard !installed else {
      return
    }

    installed = true
    let cls: AnyClass = UIViewController.self
    let original = #selector(getter: UIViewController.keyCommands)
    let swizzled = #selector(UIViewController.notifiable_keyCommands)

    guard let originalMethod = class_getInstanceMethod(cls, original),
      let swizzledMethod = class_getInstanceMethod(cls, swizzled)
    else {
      return
    }

    method_exchangeImplementations(originalMethod, swizzledMethod)
  }
}

extension UIViewController {
  @objc func notifiable_keyCommands() -> [UIKeyCommand]? {
    let existing = notifiable_keyCommands()

    guard DevelopmentShortcut.isEnabled else {
      return existing
    }

    let showMark = UIKeyCommand(
      input: "n",
      modifierFlags: .command,
      action: #selector(notifiable_showMark)
    )
    showMark.wantsPriorityOverSystemBehavior = true
    var commands = existing ?? []
    commands.append(showMark)
    return commands
  }

  @objc func notifiable_showMark() {
    DevelopmentShortcut.onShow?()
  }
}

#endif
