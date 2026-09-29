# Open Receipt

Scan. Split. Settle. Open Receipt turns a receipt into an itemized bill. Assign items to friends, split tax and tip, and send payment requests without doing the math.

## Requirements

The app runs on iPhone with iOS 27 or later. Receipt reading uses
`PrivateCloudComputeLanguageModel`, so it needs Apple Intelligence: iPhone 15 Pro, iPhone 15 Pro
Max, or any iPhone 16 or later, with Apple Intelligence turned on. On other devices you can still
create and split receipts manually.

Private Cloud Compute works only where Apple Intelligence is available. As of September 28, 2026,
Apple Intelligence is available in most countries and regions, including the EU. The exception is
China mainland: it does not work on devices bought there, or on other devices while they are in
China mainland with a China mainland Apple Account. Distribute the app in every App Store
territory except China mainland. Check
[Apple's availability page](https://support.apple.com/en-us/121115) (last published
September 14, 2026) before each release.

To develop the app:

- macOS 27+
- Xcode 27+
- Nix with `nix-command` and `flakes` enabled

## Setup

```
nix develop
make run
```

For device builds, set your Apple Developer team with `TEAM_ID=... make run-device`.
You can also copy `project.local.yml.example` to `project.local.yml` and add your
team ID. This local file is gitignored and reused by later builds.

The development shell provides the command-line tools. Xcode provides the Apple SDKs.

## Common commands

Run these from inside `nix develop`.

```
make help          # list available commands
make run           # build and run on the simulator
make run-device    # build and run on iOS hardware
make test          # run unit tests
make receipts      # evaluate receipt fixtures
make screenshots   # capture and compose App Store screenshots
make upload        # archive and upload to App Store Connect
make format        # auto-format Swift sources
make lint          # lint Swift sources (read-only)
```

Debug builds use sample receipt data and do not include the PCC entitlement. Release
builds contain no sample receipt data. They include the entitlement and use
`PrivateCloudComputeLanguageModel`:

```
make run-device release=1
```

Before you make a release build:

1. [Request PCC access from Apple](https://developer.apple.com/contact/request/private-cloud-compute/)
   for the app's developer team.
2. After approval, open [Identifiers](https://developer.apple.com/account/resources/identifiers/list),
   select `com.collinmurch.open-receipt`, enable **Access to models on Private
   Cloud Compute**, and save.
3. Run `make run-device release=1`.

You do not need to download a profile. Automatic signing creates one with the
entitlement. See Apple's [managed capabilities guide](https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities/).

## TestFlight upload

Create the app in App Store Connect with the bundle ID
`com.collinmurch.open-receipt`. Sign in to the Apple Developer account in Xcode,
then upload a build with a new build number:

```
make upload build_number=2
```

Or let Xcode pick the next build number that App Store Connect has not received:

```
make upload build_number=auto
```

With `auto`, the export step sets `manageAppVersionAndBuildNumber`, so Xcode assigns the build
number while it uploads. The local archive keeps the number from `project.yml`.

You can use an App Store Connect API key instead of the Xcode account:

```
make upload build_number=2 ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/absolute/path/to/AuthKey.p8
```

Keep the API key outside this repository. Each uploaded build must have a build
number that App Store Connect has not received before.

The receipt workspace can add people from Contacts or by name. The app requests Contacts
access only when you open the People screen. iOS can limit access to selected contacts.

## Parser development

`make receipts` builds a signed macOS `ReceiptLab.app` and evaluates receipt
fixtures with `PrivateCloudComputeLanguageModel`. Signing requires a
development team whose `com.collinmurch.open-receipt` App ID has the Private
Cloud Compute capability.

```
make receipts               # evaluate receipt fixtures
make receipts cached=1      # replay cached responses without calling PCC
```

Git ignores `Fixtures/Receipts/` because receipt scans are large and can contain
private data. See [Fixtures/README.md](Fixtures/README.md) for instructions to
add and run local fixtures.
