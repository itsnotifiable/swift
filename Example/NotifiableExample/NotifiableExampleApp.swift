import SwiftUI
import Notifiable

@main
struct NotifiableExampleApp: App {
  @UIApplicationDelegateAdaptor(NotifiableAppDelegate.self) private var appDelegate
  @StateObject private var router = ExampleRouter()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(router)
        .notifiable(
          publicKey: "ntf_pub_h4ybjm0yhkdcob6ceztzlukb0qxcctm8",
          deepLinks: exampleDeepLinks,
          onDeepLink: { url in
            Task { @MainActor in
              router.open(url: url)
            }
          }
        )
    }
  }
}
