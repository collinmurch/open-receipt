import Foundation

#if os(macOS) || !DEBUG
  import CoreGraphics
  import FoundationModels
  import Synchronization
#endif

public enum ReceiptParserError: Error, LocalizedError, Equatable {
  case emptyInput
  case modelUnavailable(String)
  case unsupportedModel
  case quotaLimitReached(resetDate: Date?)
  case rateLimited(resetDate: Date?)
  case connectionUnavailable
  case serviceUnavailable
  case timedOut
  case refused
  case tooManyPages
  case invalidResponse(String)

  public var errorDescription: String? {
    switch self {
    case .emptyInput:
      "No receipt images were supplied."
    case .modelUnavailable(let message):
      message
    case .unsupportedModel:
      "The available model does not support image-guided generation."
    case .quotaLimitReached(let resetDate):
      "You’ve reached today’s limit for reading receipts. \(Self.retryHint(after: resetDate))"
    case .rateLimited(let resetDate):
      "Too many receipts were read in a short time. \(Self.retryHint(after: resetDate))"
    case .connectionUnavailable:
      "Open Receipt couldn’t reach Private Cloud Compute. Check your connection and try again."
    case .serviceUnavailable:
      "Receipt reading is temporarily unavailable. Try again later."
    case .timedOut:
      "Reading the receipt took too long. Try again."
    case .refused:
      "These pages couldn’t be read as a receipt. Try scanning the receipt again."
    case .tooManyPages:
      "These pages are too large to read together. Remove a page and try again."
    case .invalidResponse(let message):
      "The receipt response was invalid: \(message)"
    }
  }

  /// Whether the same request can succeed when it is tried again later.
  public var isRetryable: Bool {
    switch self {
    case .emptyInput, .unsupportedModel, .refused, .tooManyPages: false
    default: true
    }
  }

  /// Whether the request failed because Private Cloud Compute could not be reached.
  public var isConnectionFailure: Bool {
    self == .connectionUnavailable
  }

  private static func retryHint(after resetDate: Date?) -> String {
    guard let resetDate, resetDate > .now else { return "Try again later." }
    let calendar = Calendar.current
    let time = resetDate.formatted(date: .omitted, time: .shortened)
    return calendar.isDateInToday(resetDate)
      ? "Try again after \(time)."
      : "Try again \(resetDate.formatted(.relative(presentation: .named)))."
  }
}

// The iOS Debug build uses sample data, and the simulator runtime lacks the parser's FoundationModels symbols.
#if os(macOS) || !DEBUG
  public enum ReceiptParser {
    /// Parses `pages`, reporting the receipt as it is read when `onPreview` is supplied.
    public static func parse(
      pages: [ReceiptPage],
      configuration: ReceiptParserConfiguration = .standard,
      onPreview: (@Sendable (ReceiptParsePreview) async -> Void)? = nil
    ) async throws -> ParsedReceipt {
      ReceiptModelContract.receipt(
        from: try await respond(pages: pages, configuration: configuration, onPreview: onPreview))
    }

    /// Returns the model response encoded as the JSON that `ReceiptModelContract.receipt(from:)` decodes.
    public static func responseData(
      pages: [ReceiptPage],
      configuration: ReceiptParserConfiguration = .standard
    ) async throws -> Data {
      try JSONEncoder().encode(
        try await respond(pages: pages, configuration: configuration, onPreview: nil))
    }

    /// Prepares a session ahead of a likely request, such as when the scanner opens. The next
    /// parse uses it. A session that is already warm is kept.
    public static func prewarm() {
      guard model.isAvailable, prewarmedSession.withLock({ $0 == nil }) else { return }
      let session = makeSession()
      session.prewarm(promptPrefix: Prompt { ReceiptModelContract.prompt })
      prewarmedSession.withLock { $0 = session }
    }

    /// The current availability and quota of the receipt model. Reading it inside a SwiftUI view
    /// body tracks changes, because the model is observable.
    public static func status() -> ReceiptModelStatus {
      if case .unavailable(let reason) = model.availability {
        return .unavailable(description(of: reason))
      }
      let quota = model.quotaUsage
      let canIncreaseLimit = quota.limitIncreaseSuggestion != nil
      switch quota.status {
      case .limitReached:
        return .limitReached(resetDate: quota.resetDate, canIncreaseLimit: canIncreaseLimit)
      case .belowLimit(let usage):
        return usage.isApproachingLimit
          ? .approachingLimit(canIncreaseLimit: canIncreaseLimit) : .available
      @unknown default:
        return .available
      }
    }

    /// Shows the system offer to raise the receipt reading limit, when one exists.
    public static func showLimitIncrease() {
      model.quotaUsage.limitIncreaseSuggestion?.show()
    }

    private static let model = PrivateCloudComputeLanguageModel()
    private static let prewarmedSession = Mutex<LanguageModelSession?>(nil)
    private static let previewInterval = Duration.milliseconds(60)

    private static func makeSession() -> LanguageModelSession {
      LanguageModelSession(model: model, instructions: ReceiptModelContract.instructions)
    }

    private static func respond(
      pages: [ReceiptPage],
      configuration: ReceiptParserConfiguration,
      onPreview: (@Sendable (ReceiptParsePreview) async -> Void)?
    ) async throws -> ReceiptModelContract.Response {
      guard !pages.isEmpty else { throw ReceiptParserError.emptyInput }

      if case .unavailable(let reason) = model.availability {
        throw ReceiptParserError.modelUnavailable(description(of: reason))
      }
      guard model.capabilities.contains(.guidedGeneration), model.capabilities.contains(.vision)
      else {
        throw ReceiptParserError.unsupportedModel
      }

      let attachments = pages.enumerated().map { index, page in
        Attachment(image(for: page, configuration: configuration), orientation: page.orientation)
          .label(ReceiptModelContract.imageLabel(at: index))
      }
      let prompt = Prompt {
        ReceiptModelContract.prompt
        attachments
      }
      let session = prewarmedSession.withLock { $0.take() } ?? makeSession()
      let options = GenerationOptions(samplingMode: .greedy)
      let contextOptions = ContextOptions(reasoningLevel: configuration.reasoningLevel.modelValue)

      do {
        guard let onPreview else {
          let response = try await session.respond(
            to: prompt,
            generating: ReceiptModelContract.Response.self,
            options: options,
            contextOptions: contextOptions)
          return response.content
        }

        let stream = session.streamResponse(
          to: prompt,
          generating: ReceiptModelContract.Response.self,
          options: options,
          contextOptions: contextOptions)
        let clock = ContinuousClock()
        var latestContent: GeneratedContent?
        var reported = ReceiptParsePreview()
        var reportedAt = clock.now
        for try await snapshot in stream {
          latestContent = snapshot.rawContent
          let preview = ReceiptModelContract.preview(from: snapshot.content)
          let isNewRow = preview.items.count != reported.items.count
          guard preview != reported, isNewRow || clock.now - reportedAt >= previewInterval
          else { continue }
          reported = preview
          reportedAt = clock.now
          await onPreview(preview)
        }
        guard let latestContent else {
          throw ReceiptParserError.invalidResponse("The model returned no content.")
        }
        return try ReceiptModelContract.Response(latestContent)
      } catch let error as CancellationError {
        throw error
      } catch {
        throw parserError(for: error)
      }
    }

    private static func image(
      for page: ReceiptPage,
      configuration: ReceiptParserConfiguration
    ) -> CGImage {
      guard let maxPixelDimension = configuration.maxPixelDimension else { return page.image }
      return ReceiptImageNormalizer.downscaled(page.image, maxPixelDimension: maxPixelDimension)
        ?? page.image
    }

    static func parserError(for error: any Error) -> ReceiptParserError {
      switch error {
      case let error as ReceiptParserError:
        return error
      case let error as PrivateCloudComputeLanguageModel.Error:
        switch error {
        case .quotaLimitReached(let details):
          return .quotaLimitReached(resetDate: details.resetDate)
        case .networkFailure:
          return .connectionUnavailable
        case .serviceUnavailable:
          return .serviceUnavailable
        @unknown default:
          return .invalidResponse(error.localizedDescription)
        }
      case let error as LanguageModelError:
        switch error {
        case .rateLimited(let details):
          return .rateLimited(resetDate: details.resetDate)
        case .timeout:
          return .timedOut
        case .guardrailViolation, .refusal:
          return .refused
        case .contextSizeExceeded:
          return .tooManyPages
        default:
          return .invalidResponse(error.localizedDescription)
        }
      case is URLError:
        return .connectionUnavailable
      default:
        return .invalidResponse(error.localizedDescription)
      }
    }

    private static func description(
      of reason: PrivateCloudComputeLanguageModel.Availability.UnavailableReason
    ) -> String {
      switch reason {
      case .deviceNotEligible:
        "Reading receipts needs a device that supports Apple Intelligence."
      case .systemNotReady:
        "Receipt reading isn’t ready yet. Make sure Apple Intelligence is turned on."
      @unknown default:
        "Receipt reading is unavailable on this device."
      }
    }
  }

  extension ReceiptParserConfiguration.ReasoningLevel {
    fileprivate var modelValue: ContextOptions.ReasoningLevel {
      switch self {
      case .light: .light
      case .moderate: .moderate
      case .deep: .deep
      }
    }
  }
#endif
