#if os(iOS)
import NotifiableCore
import SwiftUI

struct DevToasts: View {
  @EnvironmentObject private var client: NotifiableClient
  @Environment(\.scenePhase) private var scenePhase
  @State private var current: SubscriberNotification?
  @State private var queue: [SubscriberNotification] = []

  var body: some View {
    ZStack {
      if let current {
        NotificationPreview(
          notification: current,
          iconURL: client.snapshot.clientConfig?.app?.icon,
          appName: client.snapshot.clientConfig?.app?.name,
          onOpen: { open(current) },
          onDismiss: advance
        )
        .id(current.id)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(current != nil)
    .task(id: pollIdentity) {
      await poll()
    }
  }

  private var pollIdentity: String {
    let subscriberId = client.snapshot.subscriber?.id ?? ""
    return "\(subscriberId)|\(client.snapshot.permission.rawValue)"
  }

  private func poll() async {
    guard client.snapshot.permission == .granted,
      let subscriberId = client.snapshot.subscriber?.id
    else {
      return
    }

    var delay: UInt64 = 5_000_000_000
    var seen = Set<String>()
    var seenOrder: [String] = []
    let maximum: UInt64 = 30_000_000_000

    while !Task.isCancelled {
      if scenePhase != .active {
        try? await Task.sleep(nanoseconds: delay)
        continue
      }

      print("[Notifiable] Polling notifications for \(subscriberId)")

      do {
        let page = try await client.listNotifications(
          subscriberId: subscriberId,
          query: InboxQuery(page: 1, opened: false)
        )

        if Task.isCancelled || client.snapshot.subscriber?.id != subscriberId {
          return
        }

        delay = 5_000_000_000
        let fresh = selectFreshNotifications(
          page.notifications,
          nowMs: Date().timeIntervalSince1970 * 1000,
          seen: seen
        )

        for notification in fresh {
          remember(notification.id, seen: &seen, order: &seenOrder)
          let title = notification.title.isEmpty ? notification.id : notification.title
          print("[Notifiable] New notification: \(title)")
        }

        if !fresh.isEmpty {
          present(fresh)
        }
      } catch let error as NotifiableError {
        if error.code == .invalidPublicKey || error.code == .subscriberNotFound {
          return
        }

        if error.code == .rateLimited {
          delay = min(delay * 2, maximum)
        }
      } catch {
        if Task.isCancelled {
          return
        }
      }

      try? await Task.sleep(nanoseconds: delay)
    }
  }

  private func present(_ items: [SubscriberNotification]) {
    queue.append(contentsOf: items)

    if current == nil {
      current = queue.isEmpty ? nil : queue.removeFirst()
    }
  }

  private func advance() {
    current = queue.isEmpty ? nil : queue.removeFirst()
  }

  private func open(_ notification: SubscriberNotification) {
    if let deliveryId = notificationDeliveryId(notification) {
      Task { try? await client.clickDelivery(deliveryId) }
    }

    if let url = notification.url {
      print("[Notifiable] Opening \(url)")
      client.configuration.onDeepLink?(url)
    }
  }
}

private struct NotificationPreview: View {
  var notification: SubscriberNotification
  var iconURL: String?
  var appName: String?
  var onOpen: () -> Void
  var onDismiss: () -> Void
  @EnvironmentObject private var client: NotifiableClient
  @State private var overlay = false
  @State private var banner = false
  @State private var leaving = false

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(overlay ? 0.45 : 0)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
          leave()
        }
      bannerCard
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .offset(y: banner ? 0 : -240)
        .zIndex(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      withAnimation(.easeOut(duration: 0.28)) {
        overlay = true
      }
      withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.22)) {
        banner = true
      }
    }
    .task {
      try? await client.openNotification(notification.id)
      try? await Task.sleep(nanoseconds: 4_500_000_000)

      if !Task.isCancelled {
        leave()
      }
    }
  }

  private var bannerCard: some View {
    Button {
      onOpen()
      leave()
    } label: {
      HStack(alignment: .center, spacing: 12) {
        BannerIcon(url: iconURL, name: appName)
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color(white: 0.08))
              .lineLimit(1)
            Spacer(minLength: 8)
            Text("now")
              .font(.caption)
              .foregroundStyle(Color.black.opacity(0.38))
          }
          if !notification.body.isEmpty {
            Text(notification.body)
              .font(.subheadline)
              .foregroundStyle(Color.black.opacity(0.5))
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Color.white)
          .shadow(color: Color.black.opacity(0.2), radius: 18, y: 10)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var title: String {
    notification.title.isEmpty ? "Notification" : notification.title
  }

  private func leave() {
    guard !leaving else {
      return
    }

    leaving = true
    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
      banner = false
    }
    withAnimation(.easeIn(duration: 0.22).delay(0.12)) {
      overlay = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
      onDismiss()
    }
  }
}

private struct BannerIcon: View {
  var url: String?
  var name: String?

  var body: some View {
    Group {
      if let url, let iconURL = URL(string: url), iconURL.scheme == "https" || iconURL.scheme == "http" {
        AsyncImage(url: iconURL) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          default:
            fallback
          }
        }
      } else {
        fallback
      }
    }
    .frame(width: 40, height: 40)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var fallback: some View {
    ZStack {
      Color(white: 0.92)
      Text(monogram)
        .font(.headline.weight(.bold))
        .foregroundStyle(Color(white: 0.2))
    }
  }

  private var monogram: String {
    let letter = name?.first { $0.isLetter }
    return letter.map { String($0).uppercased() } ?? "N"
  }
}

private func remember(_ id: String, seen: inout Set<String>, order: inout [String]) {
  guard !seen.contains(id) else {
    return
  }

  seen.insert(id)
  order.append(id)

  if order.count > 50, let oldest = order.first {
    order.removeFirst()
    seen.remove(oldest)
  }
}

#endif
