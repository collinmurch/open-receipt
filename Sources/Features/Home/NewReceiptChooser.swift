import SwiftUI

/// A way to start a new receipt.
enum NewReceiptSource {
  case scan
  case importPhotos
  case create

  var title: String {
    switch self {
    case .scan: "Scan"
    case .importPhotos: "Import"
    case .create: "Create"
    }
  }

  var detail: String {
    switch self {
    case .scan: "Scan a paper receipt with the camera"
    case .importPhotos: "Read a receipt from your photos"
    case .create: "Enter the items yourself"
    }
  }

  var systemImage: String {
    switch self {
    case .scan: "document.viewfinder"
    case .importPhotos: "photo.on.rectangle.angled"
    case .create: "square.and.pencil"
    }
  }
}

/// Where the ways to start a receipt stand.
enum NewReceiptChooserPhase: Equatable {
  case hidden
  case raised
  /// Dropping back down, then starting `pending`, if any.
  case dropping(pending: NewReceiptSource?)
  /// Fading out in place, so another animation, such as search opening, is the only motion.
  case fading

  var isRaised: Bool { self == .raised }
}

/// Raises the ways to start a receipt from the bottom of the screen, over a backdrop that
/// dismisses on tap. Scan sits nearest the thumb and rises first. The owner sets `phase`; once
/// the chooser has dropped or faded away, `onFinish` runs with the receipt to start, if any.
struct NewReceiptChooser: View {
  private static let presentAnimation = Animation.spring(duration: 0.5, bounce: 0.22)
  private static let dropAnimation = Animation.smooth(duration: 0.28)
  private static let fadeAnimation = Animation.easeOut(duration: 0.15)
  private static let sources: [NewReceiptSource] = [.create, .importPhotos, .scan]

  let phase: NewReceiptChooserPhase
  let onChoose: (NewReceiptSource) -> Void
  let onDismiss: () -> Void
  let onFinish: (NewReceiptSource?) -> Void

  @State private var isRaised = false
  @State private var isFaded = false
  @State private var chosenCount = 0
  /// The phase last followed. It's state, so animation completions read the current phase
  /// rather than the one captured when they started.
  @State private var followedPhase = NewReceiptChooserPhase.hidden
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let riseDistance = proxy.size.height + proxy.safeAreaInsets.bottom

      ZStack(alignment: .bottom) {
        Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
          .opacity(isRaised ? 1 : 0)
          .onTapGesture(perform: onDismiss)
          .accessibilityHidden(true)

        GlassEffectContainer(spacing: 12) {
          VStack(spacing: 12) {
            ForEach(Self.sources.indices, id: \.self) { index in
              let source = Self.sources[index]
              NewReceiptSourceButton(source: source) { choose(source) }
                .rising(
                  isRaised,
                  from: riseDistance,
                  order: Self.sources.count - 1 - index,
                  reduceMotion: reduceMotion)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
      }
    }
    // Search's keyboard rises as the chooser fades for it, so the chooser stays put beneath it.
    .ignoresSafeArea(.keyboard)
    .opacity(isFaded ? 0 : 1)
    .allowsHitTesting(phase.isRaised)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, onDismiss)
    .sensoryFeedback(.selection, trigger: chosenCount)
    .onAppear { follow(phase) }
    .onChange(of: phase) { _, phase in follow(phase) }
  }

  private func choose(_ source: NewReceiptSource) {
    guard phase.isRaised else { return }
    chosenCount += 1
    onChoose(source)
  }

  private func follow(_ phase: NewReceiptChooserPhase) {
    followedPhase = phase
    switch phase {
    case .hidden:
      break
    case .raised:
      isFaded = false
      withAnimation(Self.presentAnimation) { isRaised = true }
    case .dropping(let pending):
      withAnimation(Self.dropAnimation) {
        isRaised = false
      } completion: {
        finish(pending, ifStill: phase)
      }
    case .fading:
      withAnimation(Self.fadeAnimation) {
        isFaded = true
      } completion: {
        finish(nil, ifStill: phase)
      }
    }
  }

  /// Hands back `pending` unless the phase moved on meanwhile, such as raising again mid-drop.
  private func finish(_ pending: NewReceiptSource?, ifStill expected: NewReceiptChooserPhase) {
    guard followedPhase == expected else { return }
    onFinish(pending)
  }
}

/// One way to start a receipt, as a wide glass button. Scan is tinted as the main way in.
private struct NewReceiptSourceButton: View {
  let source: NewReceiptSource
  let action: () -> Void
  @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 48
  @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 76

  var body: some View {
    Button(action: action) {
      HStack(spacing: 16) {
        Image(systemName: source.systemImage)
          .font(.title2.weight(.semibold))
          .foregroundStyle(isProminent ? Color.white : Color.accentColor)
          .frame(width: iconSize, height: iconSize)
          .background(
            isProminent ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.14), in: .circle)
        VStack(alignment: .leading, spacing: 2) {
          Text(source.title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
          Text(source.detail)
            .font(.subheadline)
            .foregroundStyle(isProminent ? Color.white.opacity(0.8) : Color.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .contentShape(.rect(cornerRadius: 28))
    }
    .buttonStyle(.plain)
    .glassEffect(
      isProminent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
      in: .rect(cornerRadius: 28)
    )
    .accessibilityLabel(source.title)
    .accessibilityHint(source.detail)
  }

  private var isProminent: Bool { source == .scan }
}
