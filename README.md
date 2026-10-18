# Notifiable for Swift

`Notifiable` registers an iOS app with [Notifiable](https://notifiable.sh), asks for notification permission, and identifies the person using the app. From the same client you can list their inbox, record that they opened or tapped a notification, and send events.

Import `Notifiable`. That is the only public module. The library requires iOS 16.

The package talks to `https://notifiable.sh/api` and sends `X-Notifiable-Key` on every request. The public key selects development or production. Apps do not pass a host or an environment name.

## Install

In Xcode, add `https://github.com/itsnotifiable/swift` and add the `Notifiable` product to the app target. The package is the library only.

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

Attach `NotifiableAppDelegate` so the SDK can receive the APNs device token. The SDK receives that token through the delegate. It does not swizzle `UIApplication`.

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

If the app already has a delegate, forward the token instead of replacing that delegate:

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

## Configure

Add `.notifiable` on the root view. It builds the client, puts it in the SwiftUI environment, and calls `start()` when the view appears. Permission is asked only when you call it from a button, or when the dashboard asks for the prompt.

```swift
ContentView()
  .notifiable(
    publicKey: "ntf_pub_...",
    deepLinks: [
      DeepLink(path: "/orders", label: "Orders"),
      DeepLink(path: "/inbox", label: "Inbox"),
    ],
    onDeepLink: { url in
      // Open this route.
    }
  )
```

| Argument | What you pass |
| --- | --- |
| `publicKey` | The key from the Notifiable dashboard. A blank key stops setup before any request. |
| `deepLinks` | Screens Notifiable can link to. Each one is `DeepLink(path:label:)`. Saved when connect succeeds. Omit it to skip that save. |
| `onDeepLink` | Called with a notification url when someone taps a development preview. |
| `logger` | Optional `debug`, `info`, `warn`, and `error` callbacks. Each one receives a message and a `[String: String]` context. |

Read the client from any child of that modifier:

```swift
struct Home: View {
  @EnvironmentObject private var notifiable: NotifiableClient

  var body: some View {
    Text(notifiable.snapshot.ready ? "Connected" : "Connecting…")
  }
}
```

`NotifiableClient` is on the main actor. Call its methods from the main actor, usually inside `Task { }`.

You can also build the client yourself and start it. Use this when the app is not rooted in the `.notifiable` modifier. Attach `NotifiableAppDelegate` first so Apple push is registered.

```swift
let notifiable = try NotifiableClient(
  publicKey: "ntf_pub_...",
  deepLinks: [DeepLink(path: "/orders", label: "Orders")],
  onDeepLink: { url in
    // Open this route.
  }
)

try await notifiable.start()
try await notifiable.requestPermission()
try await notifiable.identify(email: "ada@example.com", externalId: "user_123")
```

`NotifiableClient` keeps the session in `UserDefaults`. Pass `storage` when the app already has a store. The store is `getItem`, `setItem`, and `removeItem`.

### Public key

Create the key in the Notifiable dashboard and pass it as `publicKey`. A blank key throws `invalid_config` before the app connects.

Use the **development** key while you build, including on the iOS simulator. Use the **production** key in the build you ship. The key is what switches the app between those two modes. Keep the two keys in the matching build config and pass the one for the current build.

The same install is remembered on the device under `notifiable.session.` plus the public key. Opening the app again updates that subscriber instead of creating a new one. Permission can stay denied or undecided. The subscriber still exists.

### Permission

Ask in either of these ways. Both go through the system prompt and then save the answer.

**From a button.** Call `requestPermission()` at the moment you choose, usually after a short explanation.

```swift
Button("Enable notifications") {
  Task {
    try await notifiable.requestPermission()
  }
}
```

**Automatically.** In the Notifiable dashboard, ask this subscriber for permission. The next time the app connects, the system prompt opens on its own. That includes a later request after the person denied or dismissed the first one. Connect does not ask when the dashboard has not requested it.

The SDK owns Apple push. `provider` is `apns`. The token is the APNs device token as a hex string. `requestPermission()` asks on the main thread, then registers the device with APNs and waits for the token. A granted permission is saved with `provider: "apns"` and that token.

The example signs the app with the push entitlement so the simulator can return a device token. Connect, before the person has allowed notifications, still saves the subscriber with `not_determined` and no token.

## Development and production

| | Development key | Production key |
| --- | --- | --- |
| First launch | A sheet asks you to show or hide the Notifiable mark | No sheet |
| On screen | A draggable mark. Tap it to compare this app's bundle id with the dashboard | Nothing from Notifiable is drawn over the app |
| Notifications | A recent notification can appear as a toast at the top of the screen while the app is in the foreground and permission is `granted` | The system displays the APNs notification |
| Diagnostics | Failed SDK calls can be shared with Notifiable. The switch starts on | Nothing is sent |

### See a notification while you build

A development key polls `inbox` while a subscriber id exists, `snapshot.permission` is `granted`, and the scene is active. Send one from the dashboard and a recent unread alert appears at the top. The toast records the open. A tap records a click when the notification has `deliveryId` or an `opt` value on `url`, then calls `onDeepLink` with that url.

The poll runs every 5 seconds. A rate limit slows it. An invalid key or a missing subscriber stops it until the subscriber changes. Hiding the mark does not stop the poll.

On the simulator, permission often stays `not_determined` because there is no APNs token. The preview toast waits until permission is `granted`, which needs a token. A production key skips the sheet, the mark, and these previews.

On the simulator, Command N shows the mark again while the development view is mounted, including while a text field is focused.

The mark's sheet compares the dashboard iOS bundle id with `Bundle.main.bundleIdentifier`. A match shows a check. A mismatch names the identifier to paste into the dashboard, with a copy button. Share SDK diagnostics, on that same sheet, reports a failed SDK call once per launch. Turn it off to stop sending. [Learn what is collected](https://notifiable.sh/sdk-diagnostics).

## NotifiableClient

`snapshot` is the live state. SwiftUI updates when it changes.

Wait until `snapshot.ready` is true before `identify`, `inbox`, `notification`, `openNotification`, `clickDelivery`, or `track`. Those calls need the subscriber created at connect.

### State

**`snapshot.ready`** is true after connect has saved the subscriber.

**`snapshot.permission`** is `.granted`, `.denied`, or `.notDetermined`. The raw values are `"granted"`, `"denied"`, and `"not_determined"`.

**`snapshot.subscriber`** is the person and device Notifiable stored. It is `nil` until connect finishes. `subscriber.id` is the id you will see in the dashboard. `subscriber.externalId` is set after `identify`. `subscriber.anonymousId` is set until you identify them with an email or an external id.

**`snapshot.clientConfig`** is the app record from the dashboard: name, icon, and whether this key is `.development` or `.production`. It is `nil` until connect finishes. `clientConfig.ios` holds the dashboard iOS record, including `bundle_id`.

**`snapshot.deepLinks`** is the list of routes saved for this app. It is `nil` until that save finishes.

**`snapshot.devIndicator`** is `.enabled`, `.disabled`, or `nil` if the person has not chosen yet. It remembers whether the development mark is shown.

**`snapshot.diagnostics`** is `.enabled`, `.disabled`, or `nil`. It remembers whether development failures are shared. A missing choice means sharing is on.

**`snapshot.error`** is the last `NotifiableError`, or `nil`. Read `error.code` and `error.message`.

**`configuration`** is the public key, deep links, logger, and the other options this client was created with.

### `start()`

Connects, or does nothing when the app is already connected. `.notifiable` calls this when the view appears, so most screens never call it. Call it yourself when you built the client directly, or when you want to retry after `snapshot.error` is set.

```swift
try await notifiable.start()
```

Connect loads or creates the device id, fetches the client config, saves the subscriber, saves `deepLinks` when you passed them, and prompts when the save says permission was requested.

### `requestPermission()`

Shows the system permission prompt, then saves the result. Use it from a button. The returned value is the permission that was saved.

```swift
let permission = try await notifiable.requestPermission()
```

The same prompt also opens on connect when the dashboard has asked for it. You do not call this function for that case.

### `identify`

Attaches a real person to this device. Call it after your app knows who signed in.

```swift
let subscriber = try await notifiable.identify(
  email: "ada@example.com",
  externalId: "user_123",
  firstName: "Ada",
  lastName: "Lovelace"
)
```

`email`, `externalId`, `firstName`, and `lastName` are all optional, and at least one of them is required. A blank email or a blank external id is rejected. After an email or an external id is saved, the subscriber is no longer anonymous.

### `inbox(query:)`

Returns one page of this subscriber's notifications. The page size comes from the API, normally 20. Use it for an inbox screen.

```swift
let page = try await notifiable.inbox()
let unread = try await notifiable.inbox(query: InboxQuery(page: 1, opened: false))
```

`page` chooses the page number. `opened` keeps only opened or only unopened notifications. Leave a field out to skip that filter.

The result is `InboxPage`: `notifications`, `page`, `perPage`, and `total`. Each `SubscriberNotification` has `id`, `title`, `body`, `url`, `imageUrl`, `data`, `alert`, `status`, `opened`, `openedAt`, `createdAt`, and `deliveryId`.

`listNotifications(subscriberId:query:)` is the same request when you already have a subscriber id. `inbox` uses the id from the current session.

### `notification(_:)`

Loads one notification by id. Use it when a screen opens from a known notification id.

```swift
let item = try await notifiable.notification(id)
```

### `openNotification(_:)`

Tells Notifiable this subscriber opened that notification. Call it when your inbox marks an item as read.

```swift
try await notifiable.openNotification(id)
```

### `clickDelivery(_:)`

Tells Notifiable the person tapped that delivery. `deliveryId` is `notification.deliveryId`. Call it when they follow the notification, in addition to navigating.

```swift
if let deliveryId = item.deliveryId {
  try await notifiable.clickDelivery(deliveryId)
}
```

A development toast already does this when the preview is tapped.

### `track(name:properties:)`

Records an event for the connected subscriber. You do not pass the subscriber id. Use it for something that happened in the app, such as a completed order.

```swift
let event = try await notifiable.track(
  "order.shipped",
  properties: [
    "order": .string("1001"),
    "express": .bool(true),
  ]
)
```

`name` is required. `properties` is optional. Each value is `EventProperty.string`, `.number`, `.bool`, or `.null`. The result is `RecordedEvent`: `id`, `name`, and `subscriberId`.

### `setDevIndicator(enabled:)`

Shows or hides the development mark and remembers the choice on this device. The first-launch sheet calls this for you. Call it when your own settings screen should control the mark.

```swift
await notifiable.setDevIndicator(enabled: true)
```

A production key does not draw the mark. The choice is stored under `notifiable.dev-indicator.` plus the public key.

### `setDiagnostics(enabled:)`

Turns sharing of development failures on or off and remembers the choice. The switch on the development sheet calls this for you.

```swift
await notifiable.setDiagnostics(enabled: false)
```

A production key does not send these reports. The choice is stored under `notifiable.diagnostics.` plus the public key. Sharing starts on when the choice has not been saved yet.

## Errors

Failed calls throw `NotifiableError`. `snapshot.error.code` is the same code as the last failure from `start`, `requestPermission`, and `identify`.

| Code | What happened |
| --- | --- |
| `invalid_config` | The public key is blank, identify was called without a field, or permission was requested without Apple push registered. |
| `invalid_public_key` | Notifiable rejected the key. |
| `network` | The request did not succeed, or the response was not the expected JSON. |
| `validation_failed` | A value was rejected. |
| `subscriber_not_found` | Connect has not finished, or the subscriber no longer exists. |
| `subscriber_limit` | The project cannot add another subscriber. |
| `rate_limited` | Too many requests. Wait and try again. |
| `missing_token` | Permission is granted and no device token was returned. The default Apple push port allows a missing token and saves `not_determined` instead. |
| `missing_storage` | Reserved. The default store is `UserDefaults`. |
| `missing_provider` | Reserved from the shared error list. SwiftUI reads the client with `@EnvironmentObject`. |
| `not_implemented` | Reserved from the shared error list. |

## Tests

From the `swift` folder:

```bash
swift test
```

The tests cover connect, the subscriber body, the permission prompt, a granted permission with no token, identify clearing the anonymous id, inbox parsing, fresh development notifications, the bundle id check, and diagnostics.

## For agents

Read this section before changing the package.

Apps import `Notifiable` only. `NotifiableCore` is an internal target with no UIKit, so `swift test` runs on macOS. UIKit, UserNotifications, APNs, the device profile, `NotifiableAppDelegate`, and SwiftUI stay in the `Notifiable` target. Do not import UIKit from `NotifiableCore`.

`NotifiableCore` holds domain models, the HTTP client, `SdkAPI`, session storage, and `NotifiableClient`. The iOS target registers `ApplePushPort` and `AppleDevicePort` before the client starts. `PushPort` and `DevicePort` exist so tests can substitute them. App code uses the Apple implementations.

The host is fixed at `https://notifiable.sh/api`. Do not add a base URL or an environment argument to the public API. The `transport` initializer argument is for tests.

Subscriber saves send `sdk: "swift"`, `platform: "ios"`, and `sdk_version`. `provider` and `token` are sent only with a non-empty APNs token. A granted permission with an empty token is saved as `not_determined`.

Connect order:

1. Load or create the session: `deviceId`, `subscriberId`, `pushToken`, `anonymousId`.
2. `GET /v1/sdk/client-config`.
3. `POST /v1/sdk/subscribers`. The first save sends `anonymous_id`. Later device syncs omit identity fields.
4. `POST /v1/sdk/deep-links` when `deepLinks` was passed.
5. If `prompt_permission` is true, ask for permission and save again with `prompted: true`.

`identify` is `PATCH /v1/sdk/subscribers/{id}`. When email or external id is set, the patch sends `anonymous_id: null`.

Other routes: inbox and one notification under `/v1/sdk/subscribers/{id}/notifications`, open that notification, `POST /v1/sdk/deliveries/{id}/click`, `POST /v1/sdk/events`, and `POST /v1/sdk/diagnostics`.

`start`, `requestPermission`, and `identify` share one queue. Development diagnostics are posted once per crash fingerprint per launch, and only for a development key while sharing is on.

Command N swizzles `UIViewController.keyCommands` only on the simulator and only while a development view is mounted. Do not swizzle `UIApplication`.
# swift
