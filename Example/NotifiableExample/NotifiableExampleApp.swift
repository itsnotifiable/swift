import SwiftUI
import Notifiable

@main
struct NotifiableExampleApp: App {
  @UIApplicationDelegateAdaptor(NotifiableAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .notifiable(
          publicKey: "ntf_pub_example",
          deepLinks: [
            DeepLink(path: "/orders", label: "Orders"),
            DeepLink(path: "/inbox", label: "Inbox"),
          ],
          onDeepLink: { url in
            print("[Notifiable] Open \(url)")
          }
        )
    }
  }
}
