# Notifiable for Swift

Register an iOS app with [Notifiable](https://notifiable.sh): connect with a public key, ask for notification permission, identify the user, list their inbox, record opens and taps, and track events.

Import `Notifiable` only. Requires iOS 16. The SDK owns APNs — you do not pass a push port.

## Install

In Xcode, add `https://github.com/itsnotifiable/swift` and the `Notifiable` product to the app target.

```swift
dependencies: [
  .package(url: "https://github.com/itsnotifiable/swift", from: "0.1.1"),
],
targets: [
  .target(
    name: "MyApp",
    dependencies: [
      .product(name: "Notifiable", package: "swift"),
    ]
  ),
]
```

Attach `NotifiableAppDelegate` so the SDK receives the APNs device token (no `UIApplication` swizzling):

```swift
import SwiftUI
import Notifiable

@main
struct MyApp: App {
  @UIApplicationDelegateAdaptor(NotifiableAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
```

If the app already has a delegate, forward the token instead:

```swift
func application(
  _ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  NotifiableClient.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}

func application(
  _ application: UIApplication,
  didFailToRegisterForRemoteNotificationsWithError error: Error
) {
  NotifiableClient.didFailToRegisterForRemoteNotifications()
}
```

## Integrate

Add `.notifiable` on the root view. It builds the client, puts it in the environment, and calls `start()` when the view appears.

```swift
ContentView()
  .notifiable(
    publicKey: "ntf_pub_...",
    deepLinks: [
      DeepLink(path: "/orders", label: "Orders"),
      DeepLink(path: "/inbox", label: "Inbox"),
    ],
    onDeepLink: { url in
      // Open this route with your navigator.
    }
  )
```

| Argument | Required | Description |
| --- | --- | --- |
| `publicKey` | yes | Key from the Notifiable dashboard. Development key while building; production key for the store build. |
| `deepLinks` | no | Routes Notifiable can link to: `DeepLink(path:label:)`. |
| `onDeepLink` | no | Called with a notification url (e.g. development toast tap). |
| `logger` | no | `debug` / `info` / `warn` / `error` callbacks. |

Read the client from any child:

```swift
struct Home: View {
  @EnvironmentObject private var notifiable: NotifiableClient

  var body: some View {
    Text(notifiable.snapshot.ready ? "Connected" : "Connecting…")
  }
}
```

`NotifiableClient` is on the main actor — call methods from `Task { }` on the main actor.

Or build the client yourself (attach the app delegate first):

```swift
let notifiable = try NotifiableClient(
  publicKey: "ntf_pub_...",
  deepLinks: [DeepLink(path: "/orders", label: "Orders")],
  onDeepLink: { url in /* navigate */ }
)

try await notifiable.start()
try await notifiable.requestPermission()
try await notifiable.identify(email: "ada@example.com", externalId: "user_123")
```

Session storage defaults to `UserDefaults`. Pass `storage` (`getItem` / `setItem` / `removeItem`) to override.

### Permission

```swift
Button("Enable notifications") {
  Task {
    try await notifiable.requestPermission()
  }
}
```

Or ask from the Notifiable dashboard — the next connect opens the system prompt. `provider` is `apns`. A granted permission is saved with the hex device token. Connect before allow still saves `not_determined` with no token.

## NotifiableClient API

Wait until `snapshot.ready` is true before `identify`, `inbox`, `notification`, `openNotification`, `clickDelivery`, or `track`.

### State (`snapshot`)

| Field | Meaning |
| --- | --- |
| `ready` | Connect finished and the subscriber was saved. |
| `permission` | `.granted` / `.denied` / `.notDetermined` |
| `subscriber` | Device/person record, or `nil` until connect. |
| `clientConfig` | Dashboard app record (`ios.bundle_id`, environment). |
| `deepLinks` | Saved routes, or `nil`. |
| `devIndicator` / `diagnostics` | Development mark and crash-sharing choices. |
| `error` | Last `NotifiableError`, or `nil`. |

`configuration` holds the options this client was created with.

### Methods

**`start()`** — Connects. `.notifiable` calls this on appear.

**`requestPermission()`** — System prompt, registers for APNs, saves. Returns the saved permission.

**`identify(email:externalId:firstName:lastName:)`** — Attach a signed-in user. At least one field required; blank email/external id rejected.

```swift
try await notifiable.identify(
  email: "ada@example.com",
  externalId: "user_123",
  firstName: "Ada",
  lastName: "Lovelace"
)
```

**`inbox(query:)`** — One page of notifications (normally 20).

```swift
let page = try await notifiable.inbox()
let unread = try await notifiable.inbox(query: InboxQuery(page: 1, opened: false))
```

Each `SubscriberNotification` includes `id`, `title`, `body`, `url`, `imageUrl`, `data`, `opened`, `openedAt`, `createdAt`, `deliveryId`, and related fields.

**`notification(_:)`** / **`openNotification(_:)`** / **`clickDelivery(_:)`** — Load, mark opened, record tap.

**`track(name:properties:)`** — Event for the connected subscriber.

```swift
try await notifiable.track(
  "order.shipped",
  properties: [
    "order": .string("1001"),
    "express": .bool(true),
  ]
)
```

**`setDevIndicator(enabled:)`** / **`setDiagnostics(enabled:)`** — Development mark and diagnostics. No-ops for a production key.

## Development vs production

| | Development key | Production key |
| --- | --- | --- |
| First launch | Sheet to show/hide the Notifiable mark | No sheet |
| On screen | Draggable mark (bundle id check) | Nothing overlaid |
| Notifications | Recent unread can appear as top toasts while active + granted | System displays APNs |
| Diagnostics | Failed SDK calls can be shared | Nothing sent |

On the simulator, **⌘N** shows the mark again. Preview toasts wait until permission is `granted` (needs a token).

## Errors

Failed calls throw `NotifiableError`. `snapshot.error.code` matches the last failure from `start`, `requestPermission`, and `identify`.

| Code | Meaning |
| --- | --- |
| `invalid_config` | Blank public key, identify without a field, or permission without Apple push registered. |
| `invalid_public_key` | Key rejected. |
| `network` | Request failed or unexpected JSON. |
| `validation_failed` | Rejected value. |
| `subscriber_not_found` | Connect not finished, or subscriber gone. |
| `subscriber_limit` | Project cannot add another subscriber. |
| `rate_limited` | Too many requests. |
| `missing_token` | Granted permission but no device token (default port saves `not_determined`). |
| `missing_storage` | Reserved (default is `UserDefaults`). |
| `missing_provider` | Reserved. |
| `not_implemented` | Reserved. |

## Tests

```bash
cd swift && swift test
```

## For AI agents

### Rules

1. Import `Notifiable` only. Do not import internal targets from app code.
2. Attach `NotifiableAppDelegate` (or forward the APNs token) before requesting permission.
3. Add `.notifiable(publicKey:deepLinks:onDeepLink:)` on the root view, or construct `NotifiableClient` and call `start()`.
4. Wait for `snapshot.ready` before identify / inbox / track APIs. Call `requestPermission()` from a button inside `Task { }`.
5. After sign-in, call `identify` with `email` and/or `externalId`.
6. Wire `onDeepLink` to the app’s navigation. Record `clickDelivery` when handling taps from a custom inbox.
7. Do not invent hosts, env names, or CORS settings. Development key for local builds; production key for App Store builds.

### Integration prompt

Copy this into a coding agent when wiring the SDK into an existing iOS / SwiftUI app:

```text
Integrate the Notifiable Swift package into this iOS project.

1. Add the Notifiable SPM product (https://github.com/itsnotifiable/swift) to the app target.
2. Attach NotifiableAppDelegate via @UIApplicationDelegateAdaptor, or forward didRegisterForRemoteNotifications / didFailToRegister to NotifiableClient if an app delegate already exists.
3. On the root SwiftUI view, add .notifiable(publicKey:deepLinks:onDeepLink:) with the project’s public key (development for debug, production for release).
4. Implement onDeepLink to open the notification path with this app’s NavigationStack / router.
5. After sign-in, when snapshot.ready is true, call identify(email:externalId:).
6. Add an “Enable notifications” button that calls requestPermission() inside Task { }.
7. If there is an inbox screen, use inbox(), openNotification(_:), and clickDelivery(_:).
8. Call NotifiableClient APIs on the main actor. Do not explain CORS, API hosts, or environments — only the public key. Keep changes minimal and match existing project patterns.
```
