# open-receipt

An iOS app for parsing receipts and splitting bills.

## North star

- Native-first: Apple platforms only. Swift, SwiftUI, iOS SDK.
- Receipt parsing: DocumentScanner or imported images go directly to `PrivateCloudComputeLanguageModel`.
- Receipt recognition uses the supplied images without fixture-shaped heuristics.
- Code owns response decoding and validation; the multimodal model owns receipt recognition.

## Layout

- `App/` — iOS app entry point.
- `Sources/ReceiptCore` — multimodal model contract, response decoding, and receipt models.
- `Sources/Features`, `Sources/Models`, `Sources/Services`, `Sources/Utilities` — app-side code.
- `Tools/ReceiptLab` — CLI harness for evaluating the parser against fixtures. Built by SPM for tests and by the `ReceiptLab` macOS app target for live PCC runs.
- `Fixtures/Receipts/<name>/{fixtures/<n>.png, expected.json}` — parser test fixtures.
- `Assets/` — App Store assets. `Receipts/` holds screenshot scene inputs. `Icons/`, `ScreenshotData/`, and `Previews/` are generated and gitignored.
- `Tools/Screenshots/Capture` — UI tests that capture App Store screens. `Tools/Screenshots/Composer` — macOS SwiftUI renderer that turns captures into marketing frames.

## Development

All commands go through `make`. Never invoke `swift`, `xcodebuild`, `xcrun`, or the ReceiptLab binary directly; never pipe, redirect, grep, tail, or env-prefix a `make` call — the harness has flags for every such need (see below), and shell composition around `make` triggers sandbox escalation.

Targets:

- `make help` — list targets.
- `make build` / `make run` — build and run on the simulator.
- `make test` — full test suite. `fast=1` for SPM-only.
- `make receipts` — parser harness (primary iteration loop).
- `make icons` — export `App/open-receipt.icon` renditions to `Assets/Icons/`. Skips renditions that are already current.
- `make screenshots` — App Store screenshots (see below).
- `make format` / `make lint` — Swift formatting.
- `make clean` — remove build artifacts.

Build behavior:

- Default `make build` / `make run` uses entitlement-free `Debug`. Scan and import remain functional, but `ReceiptParsingClient.sample` supplies stable parsed data without calling PCC.
- Add `release=1` to select `Release`, attach `App/OpenReceipt.entitlements`, and use the live parser.
- Add `device=<simulator name>` to `make run` / `make test` to use a simulator other than the default `iPhone 17 Pro`, e.g. `make run device="iPhone 17 Pro Max"`.
- Keep capture and presentation shared between configurations; `ReceiptParsingClient` is the build seam.
- `ReceiptFlowModel` owns receipt-flow phases, `ReceiptDraft` owns mutable review state, and `ContactClient` is the Contacts framework seam.
- `ReceiptRecognitionCenter` owns in-flight reads. It streams partial results into `ReceiptRecognition`, stores the scan alongside the model request, and outlives the screen that started it.
- The Debug sample client streams its rows with a short delay so the reading screen can be developed without PCC.
- Opening an unread receipt never calls PCC by itself; reading is an explicit action. A read that hits the reading limit stores `recognition.deferredUntil`, and `ReceiptRecognitionCenter.resumeDeferredReads()` reads it again after the reset.
- Reads a person starts run as a `BGContinuedProcessingTask` (`ReceiptReadActivity`) so they can finish in the background.
- The receipt background is a Metal shader (`ReceiptInkWash.metal`); builds need Xcode's Metal Toolchain component.

## Harness

`make receipts` builds `ReceiptLab.app`, a signed macOS bundle carrying `App/OpenReceipt.entitlements`, and sends fixture images through `ReceiptParser` to `PrivateCloudComputeLanguageModel`, the same path the Release app uses. It diffs parsed receipts against `expected.json`. Flags:

- `of=<name|name/n|path>` — fixture selector (omit for all).
- `format=text|json|summary` — output shape (default `text`).
- `cached=1` — replay only an exact matching cached model response without consuming quota. The cache key covers the contract version, instructions, prompt, and page pixels in order; bump `ReceiptModelContract.version` when changing generation options.
- `reasoning=light|moderate|deep` / `max_pixels=<N>` — try generation settings other than the shipped `ReceiptParserConfiguration.standard`. Each variant has its own cache entries; compare accuracy and durations before changing the standard.
- `filter=<regex>` — grep output after it's produced.
- `head=<N>` / `tail=<N>` — keep first/last N lines.
- `quiet=1` — suppress per-fixture streaming (text format).

Example: `make receipts of=whole-foods-1 format=summary`.

Exit code is non-zero when any fixture fails evaluation; read the logs to confirm.

See [Fixtures/README.md](Fixtures/README.md) for instructions to add and run local fixtures.

## Screenshots

`make screenshots` runs `ScreenshotCapture` on the iPhone 17 Pro Max simulator, then `ScreenshotComposer` renders 1284x2778 frames (App Store 6.5" size) into `Assets/Previews/{light,dark}/`. Flags:

- `of=reading|split|requests|breakdown|library` — one shot.
- `cached=1` — skip capture and recompose from `Assets/ScreenshotData/{light,dark}` (seconds; use for design and copy changes).

Capture launches Debug with `-ScreenshotScenario <kind>`, which `App/ScreenshotScenario.swift` stages from the scene JSON in `Assets/Receipts/` using isolated storage. Views lifted above a frame are marked with `.screenshotHighlight(_:)`, which records their drawn frame only in that mode. Headlines and backdrops live in `StoreShot.swift`; layout in `StoreFrame.swift`.

## Conventions

- No emojis in code, comments, logs, or commit messages unless asked.
- Comments only for public API docs or genuinely non-obvious logic.
- Prefer many small, focused tests over large table-driven ones.
- Tests never call PCC; it consumes quota. Inject `ReceiptParsingClient` in app tests and a fake `ReceiptModelClient.Respond` in harness tests. Only `make receipts` makes live calls.
