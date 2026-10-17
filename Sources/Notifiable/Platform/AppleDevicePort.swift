#if os(iOS)
import Darwin
import Foundation
import NotifiableCore
import UIKit

public final class AppleDevicePort: DevicePort, @unchecked Sendable {
  public init() {}

  public func profile() async -> DeviceProfile {
    let locale = Locale.current.identifier
    let timezone = TimeZone.current.identifier
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    return DeviceProfile(
      platform: .ios,
      osVersion: emptyToNil(UIDevice.current.systemVersion),
      locale: emptyToNil(locale),
      timezone: emptyToNil(timezone),
      model: emptyToNil(machineIdentifier()),
      manufacturer: "Apple",
      appVersion: emptyToNil(version),
      ip: localIPv4()
    )
  }

  public func applicationId() async -> String? {
    emptyToNil(Bundle.main.bundleIdentifier)
  }

  public func copy(_ value: String) {
    UIPasteboard.general.string = value
  }
}

private func emptyToNil(_ value: String?) -> String? {
  guard let value, !value.isEmpty else {
    return nil
  }

  return value
}

private func machineIdentifier() -> String {
  var system = utsname()
  uname(&system)
  return withUnsafePointer(to: &system.machine) {
    $0.withMemoryRebound(to: CChar.self, capacity: 1) {
      String(cString: $0)
    }
  }
}

private func localIPv4() -> String? {
  var interfaces: UnsafeMutablePointer<ifaddrs>?

  guard getifaddrs(&interfaces) == 0, let first = interfaces else {
    return nil
  }

  defer { freeifaddrs(interfaces) }

  var pointer: UnsafeMutablePointer<ifaddrs>? = first

  while let current = pointer {
    let interface = current.pointee
    pointer = interface.ifa_next

    guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
      continue
    }

    let name = String(cString: interface.ifa_name)

    guard name == "en0" || name == "pdp_ip0" else {
      continue
    }

    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = getnameinfo(
      address,
      socklen_t(address.pointee.sa_len),
      &host,
      socklen_t(host.count),
      nil,
      0,
      NI_NUMERICHOST
    )

    guard result == 0 else {
      continue
    }

    if let ip = deviceAddress(String(cString: host)) {
      return ip
    }
  }

  return nil
}

#endif
