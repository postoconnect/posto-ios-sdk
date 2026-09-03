# Posto iOS SDK

Turn the last few turns of a chat into a matched native ad your app renders
itself. Every request is bound to the device with App Attest and goes to
`POST /v1/ads/request` — no third-party dependencies, `async/await` first.

This repository is the public binary Swift package: `Package.swift` points at
the compiled `PostoSDK.xcframework` for each release, and the README, changelog
and license live here. The SDK source is not distributed.

## Requirements

- iOS 15+
- Swift 5.9+ / Xcode 15+
- App Attest capability (entitlement
  `com.apple.developer.devicecheck.appattest-environment`) and a physical device
  for production delivery. Simulator integration uses the isolated test lane
  below.

## Installation (Swift Package Manager)

No account, SSH key or token is needed; the package downloads a prebuilt
XCFramework from `https://postoconnect.com/sdk/ios/` and verifies its
checksum.

**Xcode:** File → Add Package Dependencies… → paste
`https://github.com/postoconnect/posto-ios-sdk.git` → pick a version → add the **Posto** library.

**Package.swift:**

```swift
.package(url: "https://github.com/postoconnect/posto-ios-sdk.git", from: "4.0.0"),

// …then add "Posto" to your target's dependencies (package = the repo name):
.target(name: "MyApp", dependencies: [.product(name: "Posto", package: "posto-ios-sdk")]),
```

The framework is dynamic; Xcode embeds and signs it automatically for app
targets. The module is `PostoSDK` (the product is named Posto):

```swift
import PostoSDK
```

Register the app in the [Developer console](https://postoconnect.com/dev/register),
then open its **App profile** and complete **Production connection** with the
exact Team ID and Bundle ID. That page also shows the app's **Platform ID**,
placement IDs and **Developer test key** used below. Billable delivery starts
once the app passes publisher review; until then production requests return
`403 publisher_delivery_suspended`.

> **Before you ship:** debug builds attest in Apple's *development* App Attest
> environment, which production rejects (`app_attest_environment_invalid`).
> Verify your request → impression → click flow on a physical iPhone against
> `https://simulation.postoconnect.com` instead. Simulation is a separate stack
> with its own accounts: sign up there, register the same Team ID and Bundle ID,
> and pass that console's IDs plus `baseURL: URL(string: "https://simulation.postoconnect.com")!`
> to `Posto.register`.

## Usage

Register once at launch:

```swift
import PostoSDK

Posto.register(
    platformId: "app_your_platform",  // your app's platform id from the Developer console (required)
    placementId: "plc_feed_inline",   // the ad placement to fill; must belong to that app (required)
    trackingLevel: .persistentUserID, // omit for .none — no user id stored/sent
    // baseURL: goes here — defaults to https://postoconnect.com
    piiFilter: .standard              // default — omit unless you want .off/.enhanced
)
// register is LOCAL ONLY — it performs no network call.
```

Request an ad by handing over the recent conversation:

```swift
let ad = try await Posto.nativeFeed.requestAd(
    format: .nativeCard,
    context: AdContext(
        messages: [
            .user("Find a quiet hotel in Chicago"),
            .assistant("Here are several downtown options."),
            .user("Which one is under $250?"),
        ],
        user: AdUser(
            ageRange: .age25to34,
            gender: .women,
            location: AdLocation(country: "US", region: "Illinois", city: "Chicago")
        )
    )
)

guard let ad else {
    // No-fill is NOT an error — the backend had no relevant ad.
    return
}
render(ad)   // ad.headline, ad.body, ad.cta, ad.imageURL, ad.advertiser
```

## Simulator integration test

The iOS Simulator cannot use App Attest. Register with the App's **Developer
test key** (App profile page) to exercise the same typed request, rendering, impression, and click
APIs against a fixed Posto test ad:

```swift
Posto.registerForTesting(
    platformId: "app_your_platform",
    placementId: "plc_feed_inline",
    testKey: "your_developer_test_key",
    baseURL: URL(string: "https://simulation.postoconnect.com")!
)

let ad = try await Posto.nativeFeed.requestAd(
    format: .nativeCard,
    context: AdContext(question: "Verify my Posto integration")
)
try await ad?.trackImpression()
let destination = try await ad?.clickURL()
```

This calls `POST /v1/ads/request_non_attest`. It never enters an auction,
spends an advertiser budget, creates Developer earnings, or trains the Campaign
Agent. It always returns Posto's fixed test creative. Do not ship
`registerForTesting` as the production registration path; physical devices must
use `Posto.register` and App Attest.

For a single question, there is a shorthand:

```swift
let ad = try await Posto.nativeFeed.requestAd(
    context: AdContext(question: "cold weather trail run tips?"))
```

Completion-handler overload:

```swift
Posto.nativeFeed.requestAd(context: AdContext(question: "...")) { result in
    switch result {
    case .success(let ad): /* nil = no-fill */ break
    case .failure(let error): /* PostoError */ break
    }
}
```

Track an impression when the ad becomes visible (safe to call more than once —
the server dedupes):

```swift
try await ad.trackImpression()
```

Handle a tap (opens the destination in an in-app `SFSafariViewController`):

```swift
try await Posto.presentClick(ad, from: viewController)   // iOS only
```

## You must display a "Sponsored" label

The SDK draws no UI, but the disclosure is not optional — an ad shown without it
is not a compliant integration. The string is part of the SDK contract rather
than something the backend sends per response:

```swift
Text(AdDisclosure.sponsoredLabel())              // current locale
Text(AdDisclosure.sponsoredLabel(for: locale))   // explicit
```

## What you can send

`AdContext.messages` is the raw conversation — the SDK never summarizes or
rewrites it. Matching authority rests on the `user` turns; `assistant` turns only
help resolve references like "the first one", and cannot create ad intent on
their own.

| Rule | Behavior |
|---|---|
| Chronological, oldest first | Required |
| Starts with `.user`, strictly alternating | Required — otherwise `PostoError.invalidContext` |
| At most 3 exchanges (6 messages) | **Trimmed silently** to the most recent complete exchanges |
| 4,000 UTF-8 bytes per message | **Error, never truncated** |
| 16,000 UTF-8 bytes in total | **Error, never truncated** |
| Empty or whitespace-only content | Error |

Trimming is the one thing that happens silently, because holding a whole
conversation and sending a window of it is normal. Everything else throws: a
silently altered request would change what the person actually said, which is
worse than a rejected one. Validation runs on-device, so a contract violation
costs no network round-trip and names the offending field path.

`AdUser` is entirely optional and gates the audience only — it is never matched
semantically and never embedded. Every field is a closed vocabulary or a place
name, so there is no field in which GPS, a postal code, or a street address could
be sent. A campaign that requires a trait your request omits simply does not bid,
which is the most common cause of a no-fill.

## What you get back

```swift
ad.requestID      // quote in support requests
ad.id
ad.format         // .nativeCard, .nativeHeadless, or a newer format as a raw value
ad.advertiser
ad.headline
ad.body
ad.cta
ad.imageURL       // non-nil for .nativeCard; absent for .nativeHeadless
ad.imageAltText   // non-nil whenever imageURL is — use it for VoiceOver
```

There is no advertiser URL on `Ad`. The destination does not exist client-side
until `clickURL()` completes a signed click event with the server, so an ad
cannot be navigated to without the click being reported. Tracking tokens are
likewise private to the SDK.

## Behavior notes

- **No-fill returns `nil`**, not an error. Errors are reserved for transport
  failures, contract violations and non-2xx responses (`PostoError`).
- **Relative URLs are resolved** against the base URL (`image_url` may come back
  as `/static/...`).
- **A `.nativeCard` with no creative is rejected at decode**, rather than handed
  to you as a half-rendered ad — billing an impression for something the reader
  cannot act on is worse than reporting a no-fill.
- **Persistent user id** (`u_<UUID>`) is minted, stored in the Keychain, and
  sent only when `trackingLevel` contains `.persistentUserID`. With `.none` it is
  never generated, stored, or sent.
- **Used before `register`** is recoverable, not a crash: `requestAd` throws
  `PostoError.notRegistered`.
- **PII is redacted on-device** before the request is serialized. See below.

## PII filtering

`requestAd` scrubs identifier-shaped PII out of every message before anything
leaves the device. It targets *identifiers, not topics*: place names, brands,
prices, dates and product constraints are ad matching signal and pass through
untouched.

| `piiFilter` | Behavior |
|---|---|
| `.standard` | **Default.** Nine deterministic rules — emails, phones, payment cards (Luhn-checked), national IDs/IBANs, IPs/MACs, GPS pairs, API keys and opaque tokens become `[email]`, `[phone]`, `[card]`, … |
| `.enhanced` | `.standard`, plus on-device `NSDataDetector`/`NLTagger` for street addresses (`[address]`) and personal names (`[name]`). Place and organization names are kept. Costs some latency and can redact text that was legitimate matching signal. |
| `.off` | No redaction. Only for host apps that already scrub upstream themselves. |

The filter is deterministic, runs entirely on-device, and never throws — a
redaction failure can never break an ad request. It is defense in depth rather
than a guarantee: the backend applies the same scrub server-side, and the two
produce identical wire text for the patterns they share.

Redaction runs *before* the byte ceilings are checked, so a message that only
fits once its PII becomes a placeholder is legitimately sendable.

```swift
Posto.register(platformId: "app_your_platform", placementId: "plc_feed_inline", piiFilter: .enhanced)

// "email jane.doe@example.com or call +1 (312) 555-0142"
//   -> "email [email] or call [phone]"
```

## Attestation

Every production request carries a device-bound App Attest assertion, so the
backend can tell genuine traffic from forged traffic. Impressions and clicks
are reported through signed event APIs. The separate Simulator test lane is
fixed, non-billable, and cannot enter production delivery.

The first request per install registers an App Attest key; afterwards the SDK
only generates assertions. On a production device that cannot attest, requests
throw `PostoError.backendRelayRequired` — the SDK never falls back to an
unsigned billable request. Use your backend relay for production delivery, or
`registerForTesting` only while validating the SDK in Simulator.

> Because `isSupported` is false on every simulator, the real DeviceCheck path
> only runs on a physical device — CI exercises a stub of the attestation
> service, not Apple's implementation. Verify against
> `https://simulation.postoconnect.com` on hardware before shipping.

## Migrating

The V1 contract was replaced in place. Both the request and the response changed,
so this is a rewrite of your call sites, not a rename pass.

**Request**

- `Posto.register(platformId:)` → `Posto.register(platformId:placementId:)`. The
  platform id still authenticates the app (`X-Posto-Platform`, App Attest key
  scope); the placement id is new and names the slot to fill (`placement_id`).
- `Posto.register(attestation:)` is gone; every request is attested.
- `AdContext(question:answer:image:commerce:)` → `AdContext(messages:user:)`.
  `commerce` and `image` no longer exist — category, offer type, location, price
  and other hard constraints are extracted from the person's own words, so there
  is nothing for the host app to fill in.
- `AdUser(city:ageRange:country:)` → `AdUser(ageRange:gender:location:)`, with
  `ageRange`/`gender` now closed enums and geography under `AdLocation`.
- `requestAd` gained `format:`, defaulting to `.nativeCard`.

**Response**

- `ad.title` → `ad.headline`, and `ad.body` is new.
- `ad.imageAltText` and `ad.requestID` are new.
- `ad.format` is now `AdFormat`, not `String`.
- `ad.product`, `ad.uid`, `ad.matchScore`, `ad.url` and `ad.productURL` are gone.
  Use `clickURL()` — the advertiser's URL is no longer sent to the device at all.
- `ad.tracking` is no longer public. Use `trackImpression()` and `clickURL()`.

**Errors**

- New `PostoError.invalidContext(String)`, raised on-device before any network
  call and by the server's `422`. It carries the field path that failed.

## Support

Open an issue in this repository for integration questions. Quote the
`requestID` of the affected ad request where you have one.

## License

Copyright (c) 2026 Posto, Inc. All rights reserved. See [LICENSE](LICENSE).
