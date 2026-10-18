#if os(iOS)
import NotifiableCore
import SwiftUI

public extension View {
  func notifiable(
    publicKey: String,
    deepLinks: [DeepLink]? = nil,
    onDeepLink: (@Sendable (String) -> Void)? = nil,
    logger: (any Logger)? = nil
  ) -> some View {
    modifier(
      NotifiableModifier(
        publicKey: publicKey,
        deepLinks: deepLinks,
        onDeepLink: onDeepLink,
        logger: logger
      )
    )
  }
}

struct NotifiableModifier: ViewModifier {
  @StateObject private var client: NotifiableClient

  init(
    publicKey: String,
    deepLinks: [DeepLink]?,
    onDeepLink: (@Sendable (String) -> Void)?,
    logger: (any Logger)?
  ) {
    installNotifiableApplePlatform()
    do {
      let created = try NotifiableClient(
        publicKey: publicKey,
        logger: logger,
        deepLinks: deepLinks,
        onDeepLink: onDeepLink
      )
      _client = StateObject(wrappedValue: created)
    } catch let error as NotifiableError {
      preconditionFailure(error.message)
    } catch {
      preconditionFailure("publicKey is required")
    }
  }

  func body(content: Content) -> some View {
    content
      .environmentObject(client)
      .task {
        try? await client.start()
      }
      .overlay {
        DevelopmentLayer()
          .environmentObject(client)
      }
  }
}

private struct DevelopmentLayer: View {
  @EnvironmentObject private var client: NotifiableClient

  var body: some View {
    if client.snapshot.clientConfig?.environment == .development {
      ZStack {
        DevelopmentMark()
        DevToasts()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

#endif
