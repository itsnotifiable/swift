import SwiftUI
import Notifiable

enum ExamplePage: String, Hashable, CaseIterable {
  case orders
  case inbox

  var path: String {
    switch self {
    case .orders:
      return "/orders"
    case .inbox:
      return "/inbox"
    }
  }

  var title: String {
    switch self {
    case .orders:
      return "Orders"
    case .inbox:
      return "Inbox"
    }
  }

  var detail: String {
    "This screen is \(path). A notification whose path is \(path) opens it."
  }

  static func matching(_ url: String) -> ExamplePage? {
    let path = routePath(url)
    return allCases.first { $0.path == path }
  }
}

let exampleDeepLinks = ExamplePage.allCases.map { page in
  DeepLink(path: page.path, label: page.title)
}

@MainActor
final class ExampleRouter: ObservableObject {
  @Published var path: [ExamplePage] = []

  func open(url: String) {
    guard let page = ExamplePage.matching(url) else {
      return
    }

    path = [page]
  }
}

struct ContentView: View {
  @EnvironmentObject private var notifiable: NotifiableClient
  @EnvironmentObject private var router: ExampleRouter
  @State private var email = "ada@example.com"
  @State private var tracked: String?

  var body: some View {
    NavigationStack(path: $router.path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(notifiable.snapshot.ready ? "Connected" : "Connecting…")
            .font(.title2.bold())
          Text(status)
            .foregroundStyle(.secondary)
          Text(deepLinks)
            .font(.footnote)
            .foregroundStyle(.secondary)
          if let message = notifiable.snapshot.error?.message {
            Text(message)
              .font(.footnote)
              .foregroundStyle(.red)
          }
          Button("Enable notifications") {
            Task {
              try? await notifiable.requestPermission()
            }
          }
          .buttonStyle(.borderedProminent)
          TextField("Email", text: $email)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
          Button("Identify") {
            Task {
              try? await notifiable.identify(email: email, externalId: "user_123")
            }
          }
          .buttonStyle(.bordered)
          Button("Track order shipped") {
            Task {
              await trackOrder()
            }
          }
          .buttonStyle(.bordered)
          if let tracked {
            Text("Tracked \(tracked)")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          ForEach(ExamplePage.allCases, id: \.self) { page in
            Button(page.title) {
              router.path = [page]
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .navigationDestination(for: ExamplePage.self) { page in
        PageScreen(page: page)
      }
    }
  }

  private var status: String {
    let permission = notifiable.snapshot.permission.rawValue
    let subscriber = notifiable.snapshot.subscriber?.id ?? "No subscriber yet"
    return "\(permission)\n\(subscriber)"
  }

  private var deepLinks: String {
    guard let links = notifiable.snapshot.deepLinks else {
      return "Deep links: waiting"
    }

    if links.isEmpty {
      return "Deep links: none"
    }

    return "Deep links: \(links.map(\.path).joined(separator: ", "))"
  }

  private func trackOrder() async {
    do {
      let event = try await notifiable.track(
        name: "order.shipped",
        properties: ["order": .string("1001")]
      )
      tracked = event.name
    } catch {
      tracked = nil
    }
  }
}

private struct PageScreen: View {
  var page: ExamplePage

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(page.path)
        .font(.headline)
        .foregroundStyle(.secondary)
      Text(page.detail)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle(page.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private func routePath(_ url: String) -> String {
  if let components = URLComponents(string: url), components.scheme != nil {
    return components.path
  }

  return url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
}
