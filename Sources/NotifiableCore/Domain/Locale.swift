import Foundation

public struct LocaleParts: Sendable, Equatable {
  public var language: String?
  public var countryCode: String?
}

private let languagePattern = #"^[A-Za-z]{2,8}$"#
private let regionPattern = #"^[A-Za-z]{2}$"#
private let ipv4Pattern =
  #"^(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$"#

public func localeParts(_ locale: String?) -> LocaleParts {
  guard let locale else {
    return LocaleParts(language: nil, countryCode: nil)
  }

  let tags = locale.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
  let language = tags.first.flatMap { tag in
    tag.range(of: languagePattern, options: .regularExpression) == nil
      ? nil
      : tag.lowercased()
  }
  var countryCode: String?

  for tag in tags.dropFirst() {
    if tag.range(of: regionPattern, options: .regularExpression) != nil {
      countryCode = tag.uppercased()
    }
  }

  return LocaleParts(language: language, countryCode: countryCode)
}

public func deviceAddress(_ value: String?) -> String? {
  guard let value else {
    return nil
  }

  let address = value.trimmingCharacters(in: .whitespacesAndNewlines)

  if address.range(of: ipv4Pattern, options: .regularExpression) == nil
    || address == "0.0.0.0"
    || address.hasPrefix("127.")
  {
    return nil
  }

  return address
}
