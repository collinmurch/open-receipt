import SwiftUI
@preconcurrency import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
  let onCapture: (ReceiptScan) -> Void
  let onCancel: () -> Void
  let onFailure: (any Error) -> Void

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
    context.coordinator.onFailure = onFailure
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel, onFailure: onFailure)
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    var onCapture: (ReceiptScan) -> Void
    var onCancel: () -> Void
    var onFailure: (any Error) -> Void

    init(
      onCapture: @escaping (ReceiptScan) -> Void,
      onCancel: @escaping () -> Void,
      onFailure: @escaping (any Error) -> Void
    ) {
      self.onCapture = onCapture
      self.onCancel = onCancel
      self.onFailure = onFailure
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      Task {
        let pages = await Self.pages(of: scan)
        onCapture(ReceiptScan(pages: pages, source: .documentCamera))
      }
    }

    /// Pages are full-resolution images, so they are read off the main actor.
    private static func pages(of scan: VNDocumentCameraScan) async -> [ReceiptPage] {
      await Task.detached(priority: .userInitiated) {
        (0..<scan.pageCount).compactMap { index -> ReceiptPage? in
          let image = scan.imageOfPage(at: index)
          guard let cgImage = image.cgImage else { return nil }
          return ReceiptPage(
            image: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        }
      }.value
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onCancel()
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      onFailure(error)
    }
  }
}

extension CGImagePropertyOrientation {
  fileprivate init(_ orientation: UIImage.Orientation) {
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
