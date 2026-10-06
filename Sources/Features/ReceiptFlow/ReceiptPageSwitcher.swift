import SwiftUI
import UIKit

/// A page of a completed receipt.
enum ReceiptReviewPage: Hashable, CaseIterable {
  case receipt
  case payments

  fileprivate var title: String {
    switch self {
    case .receipt: "Receipt"
    case .payments: "Payments"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .receipt: "doc.text"
    case .payments: "dollarsign"
    }
  }
}

/// Switches a completed receipt between its items and its payment requests, by tapping a page or
/// dragging across the switcher.
///
/// The switcher is a standalone `UITabBar`, so its selection is the system glass lens that follows
/// a drag. It is deliberately not a `TabView`: a tab bar controller inside the navigation stack
/// breaks pushing and popping the receipt.
struct ReceiptPageSwitcher: View {
  /// The scale the switcher grows from as it appears, with `Animation.glassMorph`.
  static let entranceScale: CGFloat = 0.6
  private static let width: CGFloat = 240

  @Binding var selection: ReceiptReviewPage
  let tint: Color

  var body: some View {
    PageTabBar(selection: $selection, tint: tint)
      .frame(width: Self.width)
      .sensoryFeedback(.selection, trigger: selection)
  }
}

private struct PageTabBar: UIViewControllerRepresentable {
  @Binding var selection: ReceiptReviewPage
  let tint: Color

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  func makeUIViewController(context: Context) -> PageTabBarController {
    let controller = PageTabBarController()
    controller.tabBar.items = ReceiptReviewPage.allCases.enumerated().map { index, page in
      UITabBarItem(title: page.title, image: UIImage(systemName: page.systemImage), tag: index)
    }
    controller.tabBar.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: PageTabBarController, context: Context) {
    context.coordinator.selection = $selection
    let tabBar = controller.tabBar
    tabBar.tintColor = UIColor(tint)
    let index = ReceiptReviewPage.allCases.firstIndex(of: selection)
    let item = index.flatMap { tabBar.items?[$0] }
    if tabBar.selectedItem !== item {
      tabBar.selectedItem = item
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, uiViewController: PageTabBarController, context: Context
  ) -> CGSize? {
    let tabBar = uiViewController.tabBar
    let width = proposal.width ?? tabBar.intrinsicContentSize.width
    let fitted = tabBar.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: fitted.height)
  }

  @MainActor
  final class Coordinator: NSObject, UITabBarDelegate {
    var selection: Binding<ReceiptReviewPage>

    init(selection: Binding<ReceiptReviewPage>) {
      self.selection = selection
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
      let pages = ReceiptReviewPage.allCases
      guard pages.indices.contains(item.tag) else { return }
      selection.wrappedValue = pages[item.tag]
    }
  }
}

/// Keeps the tab bar out of navigation transitions. A `UITabBar` on screen when the library's
/// zoom transition starts hides the whole receipt page until the transition ends.
private final class PageTabBarController: UIViewController {
  /// How far into an arriving transition the tab bar enters, so its entrance overlaps the page
  /// settling instead of waiting for the transition's long tail.
  private static let entranceProgress: TimeInterval = 0.6

  let tabBar = UITabBar()
  private var pendingEntrance: Task<Void, Never>?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard let transitionCoordinator else {
      attachTabBar(animated: false)
      return
    }
    detachTabBar()
    if transitionCoordinator.isInteractive {
      // A pop that starts interactively, by a swipe or a back tap the system can interrupt, still
      // queues the entrance once it is let go, rather than waiting for it to finish.
      transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
        guard !context.isCancelled else { return }
        let remaining = context.transitionDuration * (1 - context.percentComplete)
        self?.scheduleEntrance(after: remaining * Self.entranceProgress)
      }
    } else {
      scheduleEntrance(after: transitionCoordinator.transitionDuration * Self.entranceProgress)
    }
    transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
      if context.isCancelled {
        self?.detachTabBar()
      } else {
        self?.attachTabBar(animated: true)
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    guard let transitionCoordinator else { return }
    detachTabBar()
    transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
      if context.isCancelled { self?.attachTabBar(animated: false) }
    }
  }

  private func scheduleEntrance(after delay: TimeInterval) {
    pendingEntrance?.cancel()
    pendingEntrance = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      self?.attachTabBar(animated: true)
    }
  }

  /// Animating matches the switcher's entrance when Done turns into it.
  private func attachTabBar(animated: Bool) {
    pendingEntrance = nil
    guard tabBar.superview == nil else { return }
    tabBar.frame = view.bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(tabBar)
    guard animated else { return }
    tabBar.alpha = 0
    tabBar.transform = CGAffineTransform(
      scaleX: ReceiptPageSwitcher.entranceScale, y: ReceiptPageSwitcher.entranceScale)
    UIView.animate(.glassMorph) {
      tabBar.alpha = 1
      tabBar.transform = .identity
    }
  }

  private func detachTabBar() {
    pendingEntrance?.cancel()
    pendingEntrance = nil
    tabBar.removeFromSuperview()
  }
}
