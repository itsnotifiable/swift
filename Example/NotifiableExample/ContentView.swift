import SwiftUI
import Notifiable

struct ContentView: View {
  @EnvironmentObject private var notifiable: NotifiableClient
  @State private var email = "ada@example.com"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(notifiable.snapshot.ready ? "Connected" : "Connecting…")
        .font(.title2.bold())
      Text(status)
        .foregroundStyle(.secondary)
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
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var status: String {
    let permission = notifiable.snapshot.permission.rawValue
    let subscriber = notifiable.snapshot.subscriber?.id ?? "No subscriber yet"
    return "\(permission)\n\(subscriber)"
  }
}
