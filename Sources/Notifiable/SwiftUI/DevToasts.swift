#if os(iOS)
import NotifiableCore
import SwiftUI

struct DevToasts: View {
  @EnvironmentObject private var client: NotifiableClient
  @Environment(\.scenePhase) private var scenePhase
  @State private var current: SubscriberNotification?
  @State private var queue: [SubscriberNotification] = []

  var body: some View {
    ZStack(alignment: .top) {
      if let current {
        ToastCard(notification: current) {
          open(current)
        }
        .padding(.top, 8)
        .allowsHitTesting(true)
        .task(id: current.id) {
          let shown = current.id
          try? await client.openNotification(shown)
          try? await Task.sleep(nanoseconds: 4_500_000_000)

          if !Task.isCancelled {
            advance()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
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

    advance()
  }
}

private struct ToastCard: View {
  var notification: SubscriberNotification
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 4) {
        Text(notification.title.isEmpty ? "Notification" : notification.title)
          .font(.headline)
        if !notification.body.isEmpty {
          Text(notification.body)
            .font(.subheadline)
        }
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
      .padding(.horizontal, 12)
    }
    .buttonStyle(.plain)
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
