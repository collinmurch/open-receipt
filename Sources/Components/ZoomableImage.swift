import SwiftUI
import UIKit

/// An image fitted to the width it's given, which pinches and double-taps to zoom and scrolls when
/// it runs taller than the screen. It stays clear of the safe area while scrolling beneath it.
struct ZoomableImage: UIViewRepresentable {
  let image: UIImage
  var cornerRadius: CGFloat = 0

  func makeUIView(context: Context) -> ZoomingImageScrollView {
    ZoomingImageScrollView(image: image, cornerRadius: cornerRadius)
  }

  func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
    view.image = image
  }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
  private static let margin: CGFloat = 16
  private static let maximumZoom: CGFloat = 4
  private static let doubleTapZoom: CGFloat = 2.5

  private let imageView = UIImageView()
  private var fittedSize: CGSize?

  var image: UIImage {
    didSet {
      guard image !== oldValue else { return }
      imageView.image = image
      fittedSize = nil
      setNeedsLayout()
    }
  }

  init(image: UIImage, cornerRadius: CGFloat) {
    self.image = image
    super.init(frame: .zero)
    delegate = self
    showsHorizontalScrollIndicator = false
    decelerationRate = .fast
    contentInsetAdjustmentBehavior = .always

    imageView.image = image
    imageView.layer.cornerRadius = cornerRadius
    imageView.layer.cornerCurve = .continuous
    imageView.clipsToBounds = true
    imageView.accessibilityIgnoresInvertColors = true
    addSubview(imageView)

    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
    doubleTap.numberOfTapsRequired = 2
    addGestureRecognizer(doubleTap)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if fittedSize != bounds.size { fit() }
    centerImage()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    fittedSize = nil
    setNeedsLayout()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    imageView
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    centerImage()
  }

  private var unobscuredSize: CGSize {
    bounds.inset(by: safeAreaInsets).size
  }

  /// Fits the width so a long card reads top to bottom, without enlarging it past where the whole
  /// card fits, which only matters on wide screens.
  private func fit() {
    fittedSize = bounds.size
    let width = unobscuredSize.width - Self.margin * 2
    let height = unobscuredSize.height - Self.margin * 2
    guard width > 0, height > 0, image.size.width > 0, image.size.height > 0 else { return }

    let fitted = min(width / image.size.width, max(height / image.size.height, 1))
    // The image view is laid out at its natural size, which zooming would otherwise scale.
    minimumZoomScale = 1
    maximumZoomScale = 1
    zoomScale = 1
    imageView.frame = CGRect(origin: .zero, size: image.size)
    contentSize = image.size
    minimumZoomScale = fitted
    maximumZoomScale = fitted * Self.maximumZoom
    zoomScale = fitted

    centerImage()
    contentOffset = CGPoint(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
  }

  /// Centers an image smaller than the screen, keeping a margin around one that is larger.
  private func centerImage() {
    let horizontal = max(Self.margin, (unobscuredSize.width - contentSize.width) / 2)
    let vertical = max(Self.margin, (unobscuredSize.height - contentSize.height) / 2)
    let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    if contentInset != inset { contentInset = inset }
  }

  @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
    if zoomScale > minimumZoomScale * 1.01 {
      setZoomScale(minimumZoomScale, animated: true)
      return
    }
    let point = recognizer.location(in: imageView)
    let scale = min(minimumZoomScale * Self.doubleTapZoom, maximumZoomScale)
    let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
    let target = CGRect(
      x: point.x - size.width / 2, y: point.y - size.height / 2,
      width: size.width, height: size.height)
    zoom(to: target, animated: true)
  }
}
