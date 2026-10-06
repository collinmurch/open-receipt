import XCTest

@testable import open_receipt

/// Builders shared by the flow model's tests.
@MainActor
protocol ReceiptFlowTesting {}

extension ReceiptFlowTesting {
  func reviewingModel(
    merchantName: String,
    recorder: SaveRecorder? = nil
  ) async -> (ReceiptFlowModel, ReceiptStorageClient) {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: merchantName), id: scan.id)
    let completed = ReceiptDocument.pending(for: scan).updating(from: draft)
    let storage = storage(document: completed, recorder: recorder)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))
    await model.performWork(using: center(storage: storage), storage: storage)
    return (model, storage)
  }

  /// Performs the model's work until it has none left, the way its view does by running it
  /// again whenever the phase changes.
  func performRemainingWork(
    of model: ReceiptFlowModel,
    using center: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    for _ in 0..<10 where model.workID != nil {
      await model.performWork(using: center, storage: storage)
    }
  }

  func center(
    parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
    storage: ReceiptStorageClient,
    access: ReadingAccess = .unlimited(),
    connectivity: ReceiptConnectivity = .immediate
  ) -> ReceiptRecognitionCenter {
    ReceiptRecognitionCenter(
      parsingClient: parsingClient,
      storage: storage,
      access: access,
      connectivity: connectivity,
      connectionRetryDelay: .zero)
  }

  func storage(for scan: ReceiptScan) -> ReceiptStorageClient {
    storage(document: .pending(for: scan))
  }

  func storage(
    document: ReceiptDocument,
    recorder: SaveRecorder? = nil,
    addPages: @escaping @Sendable (UUID, [ReceiptPage]) async throws -> ReceiptDocument = {
      _, _ in throw TestError.failed
    }
  ) -> ReceiptStorageClient {
    ReceiptStorageClient(
      create: { _, _ in document },
      createBlank: { _, _ in document },
      list: { [] },
      load: { _ in document },
      loadPages: { _ in [] },
      pageURLs: { _ in [] },
      addPages: addPages,
      deletePage: { _, _ in throw TestError.failed },
      reorderPages: { _, _ in throw TestError.failed },
      save: { document in await recorder?.append(document) },
      delete: { _ in })
  }

  func recognizedDocument(pageCount: Int, recognizedCount: Int) -> ReceiptDocument {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Saved"), id: scan.id)
    var document = ReceiptDocument.pending(for: scan).updating(from: draft)
    document.scan.pages = (0..<pageCount).map { _ in
      ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
    }
    document.recognition.pageIDs = document.scan.pages.prefix(recognizedCount).map(\.id)
    return document
  }

  func failingClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      throw TestError.failed
    }
  }

  func offlineClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.connectionUnavailable
    }
  }

  func unavailableClient(parses: CallCounter? = nil) -> ReceiptParsingClient {
    ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in
        await parses?.increment()
        throw ReceiptParserError.modelUnavailable("Unavailable.")
      },
      status: { .unavailable("Unavailable.") })
  }

  func rescanningClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      ParsedReceipt(merchantName: "Rescanned")
    }
  }

  func blankDocument(id: UUID) -> ReceiptDocument {
    let scan = ReceiptScan(id: id, pages: [], source: .manual)
    let draft = ReceiptDraft(receipt: ParsedReceipt(), id: id, backgroundStyle: .blue)
    return ReceiptDocument.pending(for: scan).updating(from: draft)
  }
}
