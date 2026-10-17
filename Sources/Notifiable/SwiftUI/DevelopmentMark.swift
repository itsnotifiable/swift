#if os(iOS)
import NotifiableCore
import SwiftUI
import UIKit

struct DevelopmentMark: View {
  @EnvironmentObject private var client: NotifiableClient
  @State private var edge: MarkEdge = .trailing
  @State private var showRecap = false
  @State private var applicationId: String?

  var body: some View {
    let choice = client.snapshot.devIndicator

    ZStack {
      if choice == nil {
        IntroSheet(name: client.snapshot.clientConfig?.app?.name ?? "this app") { enabled in
          Task { await client.setDevIndicator(enabled: enabled) }
        }
        .allowsHitTesting(true)
      }

      if choice == .enabled {
        DraggableMark(edge: $edge) {
          showRecap = true
        }
      }

      if showRecap, let config = client.snapshot.clientConfig {
        RecapSheet(
          config: config,
          applicationId: applicationId,
          diagnosticsEnabled: client.snapshot.diagnostics != .disabled,
          onDiagnostics: { enabled in
            Task { await client.setDiagnostics(enabled: enabled) }
          },
          onCopy: { value in
            client.configuration.device?.copy(value)
          },
          onHide: {
            showRecap = false
            Task { await client.setDevIndicator(enabled: false) }
          },
          onClose: { showRecap = false }
        )
        .allowsHitTesting(true)
      }
    }
    .task {
      applicationId = await client.configuration.device?.applicationId()
      #if targetEnvironment(simulator)
        DevelopmentShortcut.onShow = {
          Task { @MainActor in
            await client.setDevIndicator(enabled: true)
          }
        }
        DevelopmentShortcut.setEnabled(true)
      #endif
    }
    .onDisappear {
      #if targetEnvironment(simulator)
        DevelopmentShortcut.setEnabled(false)
        DevelopmentShortcut.onShow = nil
      #endif
    }
  }

}

private struct DraggableMark: UIViewRepresentable {
  @Binding var edge: MarkEdge
  var onTap: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(edge: $edge, onTap: onTap)
  }

  func makeUIView(context: Context) -> MarkContainer {
    let view = MarkContainer()
    view.button.addTarget(
      context.coordinator,
      action: #selector(Coordinator.tap),
      for: .touchUpInside
    )
    view.pan.addTarget(context.coordinator, action: #selector(Coordinator.pan(_:)))
    context.coordinator.container = view
    return view
  }

  func updateUIView(_ uiView: MarkContainer, context: Context) {
    context.coordinator.edge = $edge
    context.coordinator.onTap = onTap
    if !context.coordinator.isDragging {
      context.coordinator.place(animated: false)
    }
  }
}

private final class MarkContainer: UIView {
  let button = UIButton(type: .custom)
  let pan = UIPanGestureRecognizer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    button.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
    button.layer.cornerRadius = 28
    button.clipsToBounds = true
    button.backgroundColor = UIColor.black.withAlphaComponent(0.85)
    button.accessibilityLabel = "Notifiable"
    addSubview(button)
    button.addGestureRecognizer(pan)
    loadIcon()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let converted = convert(point, to: button)

    if button.point(inside: converted, with: event) {
      return button
    }

    return nil
  }

  private func loadIcon() {
    Task {
      guard let url = URL(string: "https://notifiable.sh/favicon.png"),
        let (data, _) = try? await URLSession.shared.data(from: url),
        let image = UIImage(data: data)
      else {
        return
      }

      await MainActor.run {
        self.button.setImage(image, for: .normal)
      }
    }
  }
}

private final class Coordinator: NSObject {
  var edge: Binding<MarkEdge>
  var onTap: () -> Void
  weak var container: MarkContainer?
  private var origin: CGPoint = .zero
  private var dragging = false

  init(edge: Binding<MarkEdge>, onTap: @escaping () -> Void) {
    self.edge = edge
    self.onTap = onTap
  }

  @objc func tap() {
    onTap()
  }

  @objc func pan(_ gesture: UIPanGestureRecognizer) {
    guard let container else {
      return
    }

    let translation = gesture.translation(in: container)

    switch gesture.state {
    case .began:
      dragging = true
      origin = container.button.frame.origin
    case .changed:
      container.button.frame.origin = CGPoint(
        x: origin.x + translation.x,
        y: origin.y + translation.y
      )
    case .ended, .cancelled:
      dragging = false
      let size: CGFloat = 56
      edge.wrappedValue = MarkEdge.nearest(
        in: container.bounds.size,
        mark: size,
        from: container.button.frame.origin
      )
      place(animated: true)
    default:
      break
    }
  }

  var isDragging: Bool {
    dragging
  }

  func place(animated: Bool) {
    guard let container else {
      return
    }

    let frame = edge.wrappedValue.frame(in: container.bounds.size, mark: 56)
    let updates = { container.button.frame = frame }

    if animated {
      UIView.animate(withDuration: 0.2, animations: updates)
    } else {
      updates()
    }
  }
}

private enum MarkEdge {
  case top
  case trailing
  case bottom
  case leading

  func frame(in size: CGSize, mark: CGFloat) -> CGRect {
    CGRect(origin: origin(in: size, mark: mark, drag: .zero), size: CGSize(width: mark, height: mark))
  }

  func origin(in size: CGSize, mark: CGFloat, drag: CGSize) -> CGPoint {
    let margin: CGFloat = 16
    let base: CGPoint

    switch self {
    case .top:
      base = CGPoint(x: (size.width - mark) / 2, y: margin)
    case .trailing:
      base = CGPoint(x: size.width - mark - margin, y: (size.height - mark) / 2)
    case .bottom:
      base = CGPoint(x: (size.width - mark) / 2, y: size.height - mark - margin)
    case .leading:
      base = CGPoint(x: margin, y: (size.height - mark) / 2)
    }

    return CGPoint(x: base.x + drag.width, y: base.y + drag.height)
  }

  static func nearest(in size: CGSize, mark: CGFloat, from point: CGPoint) -> MarkEdge {
    let center = CGPoint(x: point.x + mark / 2, y: point.y + mark / 2)
    let distances: [(MarkEdge, CGFloat)] = [
      (.top, center.y),
      (.bottom, size.height - center.y),
      (.leading, center.x),
      (.trailing, size.width - center.x),
    ]

    return distances.min(by: { $0.1 < $1.1 })?.0 ?? .trailing
  }
}

private struct IntroSheet: View {
  var name: String
  var onChoose: (Bool) -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.35).ignoresSafeArea()
      VStack(alignment: .leading, spacing: 16) {
        DevelopmentPill()
        Text(name)
          .font(.title2.bold())
        Text(
          "Notifiable registers this device and delivers notifications to people who accept them. \(name) is in development, so a mark can stay on screen while you test."
        )
        Text(shortcutNote)
        Button("Show the mark") { onChoose(true) }
          .buttonStyle(.borderedProminent)
          .tint(.black)
        Button("Not now") { onChoose(false) }
          .buttonStyle(.bordered)
      }
      .padding(24)
      .frame(maxWidth: 420)
      .background(.background, in: RoundedRectangle(cornerRadius: 28))
      .padding(24)
    }
  }

  private var shortcutNote: String {
    #if targetEnvironment(simulator)
      return "Drag it to the top, right, bottom, or left. It stays on that edge, clear of the screen. Tap it to compare this app's bundle id with the dashboard. If you hide it, press Command N to show it again."
    #else
      return "Drag it to the top, right, bottom, or left. It stays on that edge, clear of the screen. Tap it to compare this app's bundle id with the dashboard."
    #endif
  }
}

private struct RecapSheet: View {
  var config: DeliveryConfig
  var applicationId: String?
  var diagnosticsEnabled: Bool
  var onDiagnostics: (Bool) -> Void
  var onCopy: (String) -> Void
  var onHide: () -> Void
  var onClose: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.35).ignoresSafeArea()
        .onTapGesture(perform: onClose)
      VStack(alignment: .leading, spacing: 16) {
        DevelopmentPill()
        HStack(spacing: 12) {
          if let icon = config.app?.icon, let url = URL(string: icon) {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Color.gray.opacity(0.2)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
          VStack(alignment: .leading) {
            Text(config.app?.name ?? "This app")
              .font(.headline)
            if let description = config.app?.description {
              Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }
        bundleRow
        Toggle("Share SDK diagnostics", isOn: Binding(
          get: { diagnosticsEnabled },
          set: onDiagnostics
        ))
        Text("Help improve Notifiable by sharing SDK crash reports during development.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Link(
          "Learn what is collected",
          destination: URL(string: "https://notifiable.sh/sdk-diagnostics")!
        )
        .font(.footnote)
        #if targetEnvironment(simulator)
          Text("Press Command N to show the mark again.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        #endif
        Button("Hide the mark", action: onHide)
          .buttonStyle(.bordered)
      }
      .padding(24)
      .frame(maxWidth: 420)
      .background(.background, in: RoundedRectangle(cornerRadius: 28))
      .padding(24)
    }
  }

  @ViewBuilder
  private var bundleRow: some View {
    let configured = config.ios?["bundle_id"]?.string
    let check = packageCheck(configured: configured, applicationId: applicationId)

    VStack(alignment: .leading, spacing: 8) {
      Text("iOS bundle ID")
        .font(.subheadline.weight(.semibold))
      HStack {
        Text(configured ?? "Not set in the dashboard")
        Spacer()
        if check == .match {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else if check == .mismatch {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
        }
      }
      .font(.footnote)

      if check == .mismatch, let applicationId {
        Text("Paste \(applicationId) into the dashboard.")
          .font(.footnote)
        Button("Copy \(applicationId)") {
          onCopy(applicationId)
        }
        .font(.footnote)
      }
    }
  }
}

private struct DevelopmentPill: View {
  var body: some View {
    Text("Development")
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Color.orange.opacity(0.2), in: Capsule())
      .foregroundStyle(Color.orange)
  }
}

#endif
