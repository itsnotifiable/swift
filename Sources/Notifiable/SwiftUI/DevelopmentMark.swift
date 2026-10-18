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
      if choice == nil, let config = client.snapshot.clientConfig {
        IntroSheet(config: config) { enabled in
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
  var config: DeliveryConfig
  var onChoose: (Bool) -> Void

  var body: some View {
    DevelopmentSheet {
      AppHeading(config: config)
      Text(
        "Notifiable registers this device and delivers notifications to people who accept them. \(appName) is in development, so a mark can stay on screen while you test."
      )
      .font(.body)
      .foregroundStyle(Color.white.opacity(0.78))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      Text(shortcutNote)
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.62))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      SheetButton(title: "Show the mark", prominent: true) {
        onChoose(true)
      }
      .padding(.top, 6)
      SheetButton(title: "Not now", prominent: false) {
        onChoose(false)
      }
    }
  }

  private var appName: String {
    config.app?.name ?? "This app"
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
    DevelopmentSheet(onDismiss: onClose) {
      AppHeading(config: config)
      bundleRow
      diagnosticsBox
      #if targetEnvironment(simulator)
        Text("Press Command N to show the mark again.")
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.55))
          .multilineTextAlignment(.center)
      #endif
      SheetButton(title: "Hide the mark", prominent: false, action: onHide)
    }
  }

  @ViewBuilder
  private var bundleRow: some View {
    let configured = config.ios?["bundle_id"]?.string
    let check = packageCheck(configured: configured, applicationId: applicationId)

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("iOS bundle ID")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.white.opacity(0.45))
        Spacer()
        if check == .match {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color(red: 0.35, green: 0.82, blue: 0.45))
        } else if check == .mismatch {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.32))
        }
      }
      Text(configured ?? "Not set in the dashboard")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
      if check == .mismatch, let applicationId {
        Text("Paste \(applicationId) into the dashboard.")
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.62))
        Button {
          onCopy(applicationId)
        } label: {
          Text("Copy \(applicationId)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }

  private var diagnosticsBox: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(isOn: Binding(get: { diagnosticsEnabled }, set: onDiagnostics)) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Share SDK diagnostics")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
          Text("Help improve Notifiable by sharing SDK crash reports during development.")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.55))
        }
      }
      .tint(.white)
      Divider().overlay(Color.white.opacity(0.14))
      Link(destination: URL(string: "https://notifiable.sh/sdk-diagnostics")!) {
        Text("Learn what is collected")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
      }
    }
    .padding(14)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct DevelopmentSheet<Content: View>: View {
  var onDismiss: (() -> Void)?
  @ViewBuilder var content: () -> Content
  @State private var presented = false
  @State private var dismissing = false

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        Color.black.opacity(presented ? 0.45 : 0)
          .ignoresSafeArea()
          .onTapGesture {
            guard onDismiss != nil else {
              return
            }

            dismiss()
          }
        VStack(spacing: 14) {
          Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: 36, height: 4)
          content()
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: 460)
        .background(sheetBackground)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .offset(y: presented ? 0 : proxy.size.height)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.dismissDevelopmentSheet, DismissSheetAction(call: dismiss(then:)))
    .onAppear {
      withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
        presented = true
      }
    }
  }

  private func dismiss() {
    dismiss(then: onDismiss ?? {})
  }

  private func dismiss(then action: @escaping () -> Void) {
    guard !dismissing else {
      return
    }

    dismissing = true
    withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) {
      presented = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
      action()
    }
  }

  private var sheetBackground: some View {
    RoundedRectangle(cornerRadius: 28, style: .continuous)
      .fill(Color(red: 0.067, green: 0.067, blue: 0.067))
      .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      }
  }
}

private struct AppHeading: View {
  var config: DeliveryConfig

  var body: some View {
    VStack(spacing: 10) {
      AppIcon(url: config.app?.icon, name: config.app?.name)
      Text(config.app?.name ?? "Notifiable")
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      if let description = config.app?.description {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.white.opacity(0.62))
          .multilineTextAlignment(.center)
      }
      Text("DEVELOPMENT")
        .font(.caption2.weight(.bold))
        .tracking(0.6)
        .foregroundStyle(Color(red: 0.1, green: 0.08, blue: 0.03))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(red: 0.96, green: 0.73, blue: 0.26), in: Capsule())
    }
    .frame(maxWidth: .infinity)
  }
}

private struct AppIcon: View {
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
    .frame(width: 72, height: 72)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
    }
  }

  private var fallback: some View {
    ZStack {
      Color.white.opacity(0.08)
      Text(monogram)
        .font(.title.weight(.bold))
        .foregroundStyle(.white)
    }
  }

  private var monogram: String {
    let letter = name?.first { $0.isLetter }
    return letter.map { String($0).uppercased() } ?? "N"
  }
}

private struct DismissSheetAction {
  var call: (@escaping () -> Void) -> Void

  func callAsFunction(_ action: @escaping () -> Void) {
    call(action)
  }
}

private struct DismissSheetKey: EnvironmentKey {
  static let defaultValue = DismissSheetAction { action in
    action()
  }
}

extension EnvironmentValues {
  fileprivate var dismissDevelopmentSheet: DismissSheetAction {
    get { self[DismissSheetKey.self] }
    set { self[DismissSheetKey.self] = newValue }
  }
}

private struct SheetButton: View {
  var title: String
  var prominent: Bool
  var action: () -> Void
  @Environment(\.dismissDevelopmentSheet) private var dismissSheet

  var body: some View {
    Button {
      dismissSheet(action)
    } label: {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(prominent ? Color(red: 0.067, green: 0.067, blue: 0.067) : Color.white.opacity(0.78))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
          if prominent {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
          }
        }
    }
    .buttonStyle(.plain)
  }
}

#endif
