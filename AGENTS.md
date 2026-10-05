# open-receipt

An iOS app that reads receipts and splits bills.

## Principles

- Apple platforms only: Swift, SwiftUI, and the iOS SDK.
- Scanned or imported receipt images go straight to `PrivateCloudComputeLanguageModel` (PCC). The model reads the receipt; our code decodes and validates its response.
- Never add heuristics tailored to specific fixtures. Recognition must work from the images alone.

## Layout

- `App/` — app entry point, entitlements, and screenshot staging.
- `Sources/ReceiptCore` — model contract, response decoding, and receipt models.
- `Sources/{Features,Models,Services,Utilities}` — app code.
- `Tools/ReceiptLab` — parser evaluation harness (see [Receipt harness](#receipt-harness)).
- `Tools/Screenshots/Capture` — UI tests that capture App Store screens.
- `Tools/Screenshots/Composer` — macOS renderer that turns captures into marketing frames.
- `Fixtures/Receipts/<name>/` — parser fixtures: `fixtures/<n>.png` plus `expected.json`. See [Fixtures/README.md](Fixtures/README.md).
- `Assets/` — App Store assets. `Receipts/` holds screenshot scene data. `Icons/`, `ScreenshotData/`, and `Previews/` are generated and gitignored.

## Architecture

- `BuildChannel` decides what a build does at runtime: `development` (Debug), `testFlight` (TestFlight and App Review, found through StoreKit's sandbox environment), or `appStore`. Debug and Release otherwise behave the same; Release is just signed with the entitlements and optimized.
- `ReceiptParsingClient.standard` calls PCC, or streams `ReceiptParsingClient.sample` while Sample Receipts is on. That setting only applies in testing channels and starts on in development. The simulator has no PCC, so it can only read samples.
- `ReceiptFlowModel` owns the phases of the receipt flow.
- `ReceiptDraft` owns editable review state.
- `ContactClient` wraps the Contacts framework.
- `ReceiptRecognitionCenter` owns in-progress reads. It streams partial results into `ReceiptRecognition`, saves the scan with the model request, and keeps running after the screen that started it closes.
- Reading is always an explicit action; opening an unread receipt never calls PCC.
- User-started reads run as a `BGContinuedProcessingTask` (`ReceiptReadActivity`) so they can finish in the background.
- If a read hits the usage limit, it saves `recognition.deferredUntil`, and `ReceiptRecognitionCenter.resumeDeferredReads()` retries after the limit resets.
- `ReadingAccess` gates reads: unlimited after the one-time purchase (`PurchaseClient`, StoreKit 2), and `ReadingAccess.freeReadLimit` free reads before it. `ReceiptRecognitionCenter` admits each read under a key, so retries and deferred resumes of the same read share one free read. Reads that fail before the model answers, or stop before any items appear, give it back.
- The free read record is in `FreeReadStore`: the device keychain, iCloud Keychain, and iCloud key-value storage, merged, so reinstalling doesn't reset it. Debug uses a stand-in purchase, since unsigned builds can't reach StoreKit (`-DebugUnlimitedReading YES` starts unlocked).
- Testing channels name the build in orange at the top of Settings and under the library title, and Settings shows a Testing section: Sample Receipts, a stepper for free reads left, and Remove Purchase, which makes the build act unpurchased until it is bought or restored again. App Store builds show none of it and ignore its settings.
- The receipt background is a Metal shader (`ReceiptInkWash.metal`), so builds need Xcode's Metal Toolchain component.

## Commands

Use `make` for everything, run from the repository root.

- Never call `swift`, `xcodebuild`, `xcrun`, or the ReceiptLab binary directly.
- Run each `make` call on its own. Don't pipe, redirect, env-prefix, or chain it with `cd`, `&&`, or `;` — doing so triggers sandbox escalation. Use the built-in flags instead.

| Target | Purpose |
| --- | --- |
| `make help` | List all targets. |
| `make build` / `make run` | Build, or build and run, on the simulator. |
| `make test` | Run all tests. `fast=1` runs SPM tests only. |
| `make receipts` | Evaluate the parser against fixtures. The main iteration loop. |
| `make previews` | Generate App Store screenshots. |
| `make icons` | Export `App/open-receipt.icon` to `Assets/Icons/`, skipping up-to-date files. |
| `make format` / `make lint` | Format or lint Swift code. |
| `make clean` | Remove build artifacts. |

Build flags:

- Default builds use the `Debug` configuration: unsigned, no entitlements, and sample receipts on.
- `release=1` uses `Release` and signs with `App/OpenReceipt.entitlements`, for testing live PCC and StoreKit on a device.
- `device="<simulator name>"` picks a simulator for `run` and `test` (default `iPhone 17 Pro`).

## Receipt harness

`make receipts` builds `ReceiptLab.app`, a signed macOS app with the iOS app's PCC entitlement (`Tools/ReceiptLab/ReceiptLab.entitlements`). It sends fixture images through `ReceiptParser` to PCC, just like Release, and compares the results to each fixture's `expected.json`.

| Flag | Effect |
| --- | --- |
| `of=<name\|name/n\|path>` | Run one fixture, one sample, or a path. Omit to run all. |
| `format=text\|json\|summary` | Output format. Default `text`. |
| `cached=1` | Replay saved model responses instead of calling PCC. Only exact matches are used. |
| `reasoning=light\|moderate\|deep` | Try a different reasoning level. |
| `max_pixels=<N>` | Try a different image size limit. |
| `filter=<regex>` | Keep only matching output lines. |
| `head=<N>` / `tail=<N>` | Keep the first or last N lines. |
| `quiet=1` | Hide per-fixture progress (text format). |

Example: `make receipts of=whole-foods-1 format=summary`

- The command exits non-zero if any fixture fails. Check the output to see which.
- The cache key covers the contract version, instructions, prompt, and image pixels. Bump `ReceiptModelContract.version` when changing generation options.
- `reasoning` and `max_pixels` override the shipped `ReceiptParserConfiguration.standard` and get their own cache entries. Compare accuracy and speed before changing the standard.

## Screenshots

`make previews` captures screens on the iPhone 17 Pro Max simulator, then renders 1284x2778 frames (App Store 6.5") into `Assets/Previews/{light,dark}/`.

- `of=reading|split|requests|breakdown|share|library|paywall` renders one screenshot.
- `paywall` is the in-app purchase's App Review screenshot. It is copied unframed, light only, to `Assets/Previews/review/`.
- `cached=1` skips capture and re-renders from `Assets/ScreenshotData/`. Use it for design and copy changes.

How it works:

- Capture launches Debug with `-ScreenshotScenario <kind>`. `App/ScreenshotScenario.swift` sets up the scene from JSON in `Assets/Receipts/` using isolated storage.
- Views that float above the frame use `.screenshotHighlight(_:)`, which records their position only in screenshot mode.
- Headlines and backgrounds are in `StoreShot.swift`; layout is in `StoreFrame.swift`.

## Conventions

- No emojis in code, comments, logs, or commit messages unless asked.
- Comment only public APIs or genuinely non-obvious logic.
- Prefer many small, focused tests over large table-driven ones.
- Tests must never call PCC, since it uses quota. Inject `ReceiptParsingClient` in app tests (never `.standard` or `.live`) and a fake `ReceiptModelClient.Respond` in harness tests. Only `make receipts` makes live calls.
