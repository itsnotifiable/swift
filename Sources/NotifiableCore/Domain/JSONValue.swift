import Foundation

public enum JSONValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  public var string: String? {
    if case let .string(value) = self {
      return value.isEmpty ? nil : value
    }

    return nil
  }

  public var object: [String: JSONValue]? {
    if case let .object(value) = self {
      return value
    }

    return nil
  }
}

enum JSON {
  static func value(from data: Data) throws -> JSONValue {
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return value(from: object)
  }

  static func value(from object: Any) -> JSONValue {
    if object is NSNull {
      return .null
    }

    if let string = object as? String {
      return .string(string)
    }

    if let number = object as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .bool(number.boolValue)
      }

      return .number(number.doubleValue)
    }

    if let dictionary = object as? [String: Any] {
      return .object(dictionary.mapValues(value(from:)))
    }

    if let list = object as? [Any] {
      return .array(list.map(value(from:)))
    }

    return .null
  }

  static func object(from value: JSONValue) -> Any {
    switch value {
    case let .string(string):
      return string
    case let .number(number):
      if number.rounded() == number, number <= Double(Int.max), number >= Double(Int.min) {
        return Int(number)
      }

      return number
    case let .bool(bool):
      return bool
    case let .object(fields):
      return fields.mapValues(object(from:))
    case let .array(items):
      return items.map(object(from:))
    case .null:
      return NSNull()
    }
  }

  static func data(from fields: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: fields)
  }
}
