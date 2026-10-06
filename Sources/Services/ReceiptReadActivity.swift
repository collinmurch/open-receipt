import BackgroundTasks
import Synchronization
import UIKit

/// Keeps a receipt read running after the app moves to the background. A read someone started
/// becomes a continued processing task, which the system shows with its progress and lets finish;
/// otherwise the app asks for the short background time UIKit allows.
@MainActor
final class ReceiptReadActivity {
  private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
  private let continuedProcessing: ContinuedProcessing?

  /// `onExpiration` runs when the person stops the read from its system progress or the system
  /// ends it, and must stop the read.
  init(continuesInBackground: Bool, onExpiration: @escaping @MainActor @Sendable () -> Void) {
    continuedProcessing =
      continuesInBackground ? ContinuedProcessing.submit(onExpiration: onExpiration) : nil
    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Read receipt") {
      [weak self] in
      MainActor.assumeIsolated { self?.endBackgroundTask() }
    }
  }

  func reportProgress(itemCount: Int) {
    continuedProcessing?.update(itemCount: itemCount)
  }

  func end(succeeded: Bool) {
    continuedProcessing?.finish(succeeded: succeeded)
    endBackgroundTask()
  }

  private func endBackgroundTask() {
    guard backgroundTaskID != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTaskID)
    backgroundTaskID = .invalid
  }
}

/// State sits behind a mutex, because the system calls the launch and expiration handlers on its
/// own queues.
private final class ContinuedProcessing: Sendable {
  private static let totalUnitCount: Int64 = 100

  private struct State {
    /// Only touched under the mutex. The system hands the task over once, at launch.
    nonisolated(unsafe) var task: BGContinuedProcessingTask?
    var completedUnitCount: Int64 = 5
    var itemCount = 0
    var result: Bool?
  }

  private let state = Mutex(State())
  private let onExpiration: @MainActor @Sendable () -> Void

  private init(onExpiration: @escaping @MainActor @Sendable () -> Void) {
    self.onExpiration = onExpiration
  }

  /// Submits a task for the read, or returns `nil` when the task can't be registered. A request the
  /// system declines never starts, so the read simply runs without system progress UI.
  static func submit(
    onExpiration: @escaping @MainActor @Sendable () -> Void
  ) -> ContinuedProcessing? {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.collinmurch.open-receipt"
    let identifier = "\(bundleID).read.\(UUID().uuidString)"
    let processing = ContinuedProcessing(onExpiration: onExpiration)
    let scheduler = BGTaskScheduler.shared
    let isRegistered = scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let task = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      processing.start(task)
    }
    guard isRegistered else { return nil }

    let request = BGContinuedProcessingTaskRequest(
      identifier: identifier,
      title: "Reading Receipt",
      subtitle: "Items appear as they’re read.")
    request.strategy = .fail
    scheduler.submitTaskRequest(request) { _ in }
    return processing
  }

  func update(itemCount: Int) {
    state.withLock { state in
      guard state.result == nil, itemCount != state.itemCount else { return }
      state.itemCount = itemCount
      state.completedUnitCount = min(90, 10 + Int64(itemCount) * 4)
      guard let task = state.task else { return }
      task.progress.completedUnitCount = state.completedUnitCount
      task.updateTitle(task.title, subtitle: Self.subtitle(itemCount: itemCount))
    }
  }

  func finish(succeeded: Bool) {
    state.withLock { state in
      guard state.result == nil else { return }
      state.result = succeeded
      guard let task = state.task else { return }
      state.task = nil
      task.progress.completedUnitCount = Self.totalUnitCount
      task.setTaskCompleted(success: succeeded)
    }
  }

  private func start(_ task: BGContinuedProcessingTask) {
    state.withLock { state in
      if let result = state.result {
        task.setTaskCompleted(success: result)
        return
      }
      task.progress.totalUnitCount = Self.totalUnitCount
      task.progress.completedUnitCount = state.completedUnitCount
      task.expirationHandler = { [weak self] in self?.expire() }
      state.task = task
    }
  }

  private func expire() {
    let didExpire = state.withLock { state in
      guard state.result == nil else { return false }
      state.result = false
      state.task?.setTaskCompleted(success: false)
      state.task = nil
      return true
    }
    guard didExpire else { return }
    let onExpiration = onExpiration
    Task { @MainActor in onExpiration() }
  }

  private static func subtitle(itemCount: Int) -> String {
    String(inflecting: "Read ^[\(itemCount) item](inflect: true)")
  }
}
