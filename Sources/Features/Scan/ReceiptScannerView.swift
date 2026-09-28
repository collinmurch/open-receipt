import SwiftUI
@preconcurrency import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
  var onCapture: (ReceiptScan) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(
    _ uiViewController: VNDocumentCameraViewController,
    context: Context
  ) {
    context.coordinator.onCapture = onCapture
    context.coordinator.onCancel = onCancel
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel)
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    var onCapture: (ReceiptScan) -> Void
    var onCancel: () -> Void

    init(
      onCapture: @escaping (ReceiptScan) -> Void,
      onCancel: @escaping () -> Void
    ) {
      self.onCapture = onCapture
      self.onCancel = onCancel
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
      let pages = images.enumerated().compactMap { index, image -> ReceiptPage? in
        guard let cgImage = image.cgImage else { return nil }
        return ReceiptPage(
          image: cgImage,
          orientation: CGImagePropertyOrientation(image.imageOrientation),
          sourceURL: URL(fileURLWithPath: "document-scanner"),
          pageIndex: index)
      }
      onCapture(ReceiptScan(pages: pages, source: .documentCamera))
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onCancel()
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      onCancel()
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
