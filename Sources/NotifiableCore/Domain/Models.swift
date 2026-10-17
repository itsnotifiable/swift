import Foundation

public struct DeepLink: Sendable, Equatable {
  public var path: String
  public var label: String

  public init(path: String, label: String) {
    self.path = path
    self.label = label
  }
}

public enum EventProperty: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
}

public struct RecordedEvent: Sendable, Equatable {
  public var id: String
  public var name: String
  public var subscriberId: String

  public init(id: String, name: String, subscriberId: String) {
    self.id = id
    self.name = name
    self.subscriberId = subscriberId
  }
}

public enum DevIndicatorChoice: String, Sendable, Equatable {
  case enabled
  case disabled
}

public enum DiagnosticsChoice: String, Sendable, Equatable {
  case enabled
  case disabled
}

public struct StackFrame: Sendable, Equatable {
  public var function: String
  public var file: String
  public var line: Int

  public init(function: String, file: String, line: Int) {
    self.function = function
    self.file = file
    self.line = line
  }
}

public struct DiagnosticCrash: Sendable, Equatable {
  public var id: String
  public var kind: String
  public var sdk: String
  public var sdkVersion: String
  public var platform: MobilePlatform
  public var occurredAt: String
  public var errorType: String
  public var errorMessage: String
  public var frames: [StackFrame]
  public var subscriberId: String?

  public init(
    id: String,
    sdkVersion: String,
    platform: MobilePlatform,
    occurredAt: String,
    errorType: String,
    errorMessage: String,
    frames: [StackFrame],
    subscriberId: String?
  ) {
    self.id = id
    self.kind = "crash"
    self.sdk = notifiableSDKName
    self.sdkVersion = sdkVersion
    self.platform = platform
    self.occurredAt = occurredAt
    self.errorType = errorType
    self.errorMessage = errorMessage
    self.frames = frames
    self.subscriberId = subscriberId
  }
}

public enum PackageCheck: String, Sendable, Equatable {
  case match
  case mismatch
}

public func packageCheck(configured: String?, applicationId: String?) -> PackageCheck? {
  guard let applicationId, !applicationId.isEmpty else {
    return nil
  }

  if configured == nil || configured != applicationId {
    return .mismatch
  }

  return .match
}

public struct DescribedCrash: Sendable, Equatable {
  public var type: String
  public var message: String
  public var frames: [StackFrame]
}

public func describeCrash(_ error: Error, symbols: [String] = []) -> DescribedCrash {
  let frames = Array(symbols.compactMap(parseFrame).prefix(20))

  if let notifiable = error as? NotifiableError {
    return DescribedCrash(
      type: limit("NotifiableError.\(notifiable.code.rawValue)", 200),
      message: limit(notifiable.message, 2000),
      frames: frames
    )
  }

  let name = String(describing: type(of: error))
  return DescribedCrash(
    type: limit(name.isEmpty ? "Error" : name, 200),
    message: limit(error.localizedDescription, 2000),
    frames: frames
  )
}

public func crashFingerprint(type: String, message: String, frames: [StackFrame]) -> String {
  let site: String

  if let frame = frames.first {
    site = "\(frame.function)|\(frame.file)|\(frame.line)"
  } else {
    site = ""
  }

  return "\(type)|\(message)|\(site)"
}

private let uuidPattern =
  #"^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$"#

public func diagnosticSubscriberId(_ subscriberId: String?) -> String? {
  guard let subscriberId,
    subscriberId.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil
  else {
    return nil
  }

  return subscriberId
}

private func parseFrame(_ line: String) -> StackFrame? {
  let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.isEmpty {
    return nil
  }

  let patterns = [
    #"^\s*at\s+(?:async\s+)?(.*?)\s+\((?:address at\s+)?(.+):(\d+):\d+\)$"#,
    #"^(.+?)@(.+):(\d+):\d+$"#,
    #"^\s*at\s+(?:async\s+)?(.+):(\d+):\d+$"#,
  ]

  for pattern in patterns {
    if let frame = frame(in: trimmed, pattern: pattern) {
      return frame
    }
  }

  return swiftFrame(trimmed)
}

private func frame(in line: String, pattern: String) -> StackFrame? {
  guard let expression = try? NSRegularExpression(pattern: pattern),
    let match = expression.firstMatch(
      in: line,
      range: NSRange(line.startIndex..., in: line)
    )
  else {
    return nil
  }

  func group(_ index: Int) -> String {
    guard let range = Range(match.range(at: index), in: line) else {
      return ""
    }

    return String(line[range])
  }

  let rawFunction = group(1)
  let rawFile: String
  let rawLine: String

  if match.numberOfRanges > 3 {
    rawFile = group(2)
    rawLine = group(3)
  } else {
    rawFile = group(1)
    rawLine = group(2)
  }

  return makeFrame(function: rawFunction, file: rawFile, line: rawLine)
}

private func swiftFrame(_ line: String) -> StackFrame? {
  let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)

  guard parts.count >= 4 else {
    return nil
  }

  let module = parts[1]
  let symbol = parts.dropFirst(3).joined(separator: " ")
  let function = symbol.split(separator: "+").first.map {
    String($0).trimmingCharacters(in: .whitespaces)
  }

  guard let function, !function.isEmpty, !module.isEmpty else {
    return nil
  }

  return StackFrame(function: limit(function, 200), file: limit(module, 500), line: 1)
}

private func makeFrame(function: String, file: String, line: String) -> StackFrame? {
  guard let lineNumber = Int(line), lineNumber >= 1 else {
    return nil
  }

  let fileName = limit(file.trimmingCharacters(in: .whitespaces), 500)
  let name = function.trimmingCharacters(in: .whitespaces)

  if fileName.isEmpty {
    return nil
  }

  return StackFrame(
    function: limit(name.isEmpty ? "anonymous" : name, 200),
    file: fileName,
    line: lineNumber
  )
}

private func limit(_ value: String, _ max: Int) -> String {
  if value.count <= max {
    return value
  }

  return String(value.prefix(max))
}
