public enum PermissionStatus: String, Sendable, Equatable {
  case granted
  case denied
  case notDetermined = "not_determined"
}

public enum DevicePlatform: String, Sendable, Equatable {
  case ios
  case android
  case web
}

public enum MobilePlatform: String, Sendable, Equatable {
  case ios
  case android
}

public enum PushProvider: String, Sendable, Equatable {
  case apns
  case fcm
  case expo
  case webPush = "web_push"
}

public struct Subscriber: Sendable, Equatable {
  public var id: String
  public var environment: String
  public var platform: DevicePlatform
  public var permission: PermissionStatus
  public var sdk: String?
  public var provider: PushProvider?
  public var deviceId: String?
  public var externalId: String?
  public var anonymousId: String?
  public var promptPermission: Bool

  public init(
    id: String,
    environment: String,
    platform: DevicePlatform,
    permission: PermissionStatus,
    sdk: String?,
    provider: PushProvider?,
    deviceId: String?,
    externalId: String?,
    anonymousId: String?,
    promptPermission: Bool
  ) {
    self.id = id
    self.environment = environment
    self.platform = platform
    self.permission = permission
    self.sdk = sdk
    self.provider = provider
    self.deviceId = deviceId
    self.externalId = externalId
    self.anonymousId = anonymousId
    self.promptPermission = promptPermission
  }
}

public struct StoredSession: Sendable, Equatable {
  public var deviceId: String
  public var subscriberId: String?
  public var pushToken: String?
  public var anonymousId: String?

  public init(
    deviceId: String,
    subscriberId: String?,
    pushToken: String?,
    anonymousId: String?
  ) {
    self.deviceId = deviceId
    self.subscriberId = subscriberId
    self.pushToken = pushToken
    self.anonymousId = anonymousId
  }
}

public struct DeviceProfile: Sendable, Equatable {
  public var platform: MobilePlatform
  public var osVersion: String?
  public var locale: String?
  public var timezone: String?
  public var model: String?
  public var manufacturer: String?
  public var appVersion: String?
  public var ip: String?

  public init(
    platform: MobilePlatform,
    osVersion: String? = nil,
    locale: String? = nil,
    timezone: String? = nil,
    model: String? = nil,
    manufacturer: String? = nil,
    appVersion: String? = nil,
    ip: String? = nil
  ) {
    self.platform = platform
    self.osVersion = osVersion
    self.locale = locale
    self.timezone = timezone
    self.model = model
    self.manufacturer = manufacturer
    self.appVersion = appVersion
    self.ip = ip
  }
}

public struct SubscriberWrite: Sendable, Equatable {
  public var deviceId: String
  public var platform: MobilePlatform
  public var permission: PermissionStatus
  public var provider: PushProvider?
  public var token: String?
  public var anonymousId: String?
  public var prompted: Bool?
  public var osVersion: String?
  public var locale: String?
  public var timezone: String?
  public var model: String?
  public var manufacturer: String?
  public var appVersion: String?
  public var ip: String?
  public var language: String?
  public var countryCode: String?
  public var sdkVersion: String?

  public init(
    deviceId: String,
    platform: MobilePlatform,
    permission: PermissionStatus,
    provider: PushProvider? = nil,
    token: String? = nil,
    anonymousId: String? = nil,
    prompted: Bool? = nil,
    osVersion: String? = nil,
    locale: String? = nil,
    timezone: String? = nil,
    model: String? = nil,
    manufacturer: String? = nil,
    appVersion: String? = nil,
    ip: String? = nil,
    language: String? = nil,
    countryCode: String? = nil,
    sdkVersion: String? = nil
  ) {
    self.deviceId = deviceId
    self.platform = platform
    self.permission = permission
    self.provider = provider
    self.token = token
    self.anonymousId = anonymousId
    self.prompted = prompted
    self.osVersion = osVersion
    self.locale = locale
    self.timezone = timezone
    self.model = model
    self.manufacturer = manufacturer
    self.appVersion = appVersion
    self.ip = ip
    self.language = language
    self.countryCode = countryCode
    self.sdkVersion = sdkVersion
  }
}

public struct SubscriberIdentity: Sendable, Equatable {
  public var email: String?
  public var externalId: String?
  public var firstName: String?
  public var lastName: String?
  public var includesFirstName: Bool
  public var includesLastName: Bool
  public var anonymousId: String??

  public init(
    email: String? = nil,
    externalId: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil,
    includesFirstName: Bool = false,
    includesLastName: Bool = false,
    anonymousId: String?? = nil
  ) {
    self.email = email
    self.externalId = externalId
    self.firstName = firstName
    self.lastName = lastName
    self.includesFirstName = includesFirstName
    self.includesLastName = includesLastName
    self.anonymousId = anonymousId
  }
}

public struct IdentifyInput: Sendable, Equatable {
  public var email: String?
  public var externalId: String?
  public var firstName: String?
  public var lastName: String?
  public var includesFirstName: Bool
  public var includesLastName: Bool

  public init(
    email: String? = nil,
    externalId: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil,
    includesFirstName: Bool = false,
    includesLastName: Bool = false
  ) {
    self.email = email
    self.externalId = externalId
    self.firstName = firstName
    self.lastName = lastName
    self.includesFirstName = includesFirstName
    self.includesLastName = includesLastName
  }
}

public enum ClientEnvironment: String, Sendable, Equatable {
  case development
  case production
}

public struct ClientApp: Sendable, Equatable {
  public var name: String?
  public var description: String?
  public var icon: String?

  public init(name: String?, description: String?, icon: String?) {
    self.name = name
    self.description = description
    self.icon = icon
  }
}

public struct DeliveryConfig: Sendable, Equatable {
  public var environment: ClientEnvironment?
  public var app: ClientApp?
  public var android: [String: JSONValue]?
  public var ios: [String: JSONValue]?
  public var web: [String: JSONValue]?

  public init(
    environment: ClientEnvironment?,
    app: ClientApp?,
    android: [String: JSONValue]?,
    ios: [String: JSONValue]?,
    web: [String: JSONValue]?
  ) {
    self.environment = environment
    self.app = app
    self.android = android
    self.ios = ios
    self.web = web
  }
}
