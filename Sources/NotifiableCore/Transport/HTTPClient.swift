import Foundation

public struct HTTPResult: Sendable {
  public var statusCode: Int
  public var body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public protocol HTTPSending: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPResult
}

public struct URLSessionHTTP: HTTPSending {
  public init() {}

  public func send(_ request: URLRequest) async throws -> HTTPResult {
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw NotifiableError(code: .network, message: "The response was not HTTP.")
    }

    return HTTPResult(statusCode: http.statusCode, body: data)
  }
}

struct HTTPClient {
  var baseURL: URL
  var publicKey: String
  var transport: any HTTPSending

  func request(method: String, path: String, body: [String: Any]? = nil) async throws -> JSONValue? {
    let url = join(baseURL, path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(publicKey, forHTTPHeaderField: "X-Notifiable-Key")

    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSON.data(from: body)
    }

    let response: HTTPResult

    do {
      response = try await transport.send(request)
    } catch let error as NotifiableError {
      throw error
    } catch {
      throw NotifiableError(code: .network, message: error.localizedDescription)
    }

    return try readEnvelope(response.body)
  }
}

private let apiErrorCodes: [String: NotifiableErrorCode] = [
  "INVALID_PUBLIC_KEY": .invalidPublicKey,
  "VALIDATION_FAILED": .validationFailed,
  "SUBSCRIBER_NOT_FOUND": .subscriberNotFound,
  "SUBSCRIBER_LIMIT_REACHED": .subscriberLimit,
  "RATE_LIMIT_EXCEEDED": .rateLimited,
]

private func readEnvelope(_ data: Data) throws -> JSONValue? {
  let payload: JSONValue

  do {
    payload = try JSON.value(from: data)
  } catch {
    throw NotifiableError(code: .network, message: "The response was not JSON.")
  }

  guard let fields = payload.object, case let .string(status) = fields["status"] else {
    throw NotifiableError(code: .network, message: "The response envelope was invalid.")
  }

  if status == "success" {
    return fields["data"]
  }

  let code: String

  if case let .string(value) = fields["code"] {
    code = value
  } else {
    code = ""
  }

  let mapped = apiErrorCodes[code] ?? .network
  let fallback: String

  if case let .string(message) = fields["message"] {
    fallback = message
  } else {
    fallback = "The request failed."
  }

  throw NotifiableError(code: mapped, message: errorMessage(fields["error"], fallback: fallback))
}

private func errorMessage(_ error: JSONValue?, fallback: String) -> String {
  guard let details = error?.object?["details"] else {
    return fallback
  }

  guard case let .array(items) = details else {
    return fallback
  }

  let messages = items.compactMap { item -> String? in
    guard case let .string(message) = item.object?["message"] else {
      return nil
    }

    return message
  }

  return messages.isEmpty ? fallback : messages.joined(separator: " ")
}

private func join(_ baseURL: URL, _ path: String) -> URL {
  let root = baseURL.absoluteString.hasSuffix("/")
    ? String(baseURL.absoluteString.dropLast())
    : baseURL.absoluteString
  let suffix = path.hasPrefix("/") ? path : "/\(path)"
  return URL(string: root + suffix) ?? baseURL
}
