# Changelog

## 3.1.0

- Distributed as a compiled `Posto.xcframework` (iOS device + Simulator)
  through the public binary Swift package
  <https://github.com/postoconnect/posto-ios-sdk>. The source package is no
  longer public; installation and usage documentation lives in that
  repository.
- `PostoCore` is folded into the `Posto` module. Every type keeps its name and
  `import Posto` already exposed all of them since 3.0.0, so integrator code
  is unchanged; only an explicit `import PostoCore` has to go.
- The binary targets iOS 15+ only. The macOS platform of the source package
  exists for tests and is not part of the distributed framework.
- No API changes.

## 3.0.0

**The V1 contract was replaced in place.** Production had no external SDK users,
so there is no V2 and no compatibility period: the old `commerce`/`question`/
`answer`/`image` request and the old `ads[]` response are simply gone, and a
request in the old shape now fails against the new backend.

Its own major rather than a continuation of 2.0: the wire contract changed on
both the request and the response side, so 2.x-beta adopters must rewrite call
sites, not just recompile. The 2.0 line is abandoned without ever tagging stable —
`2.0.0-beta.1`/`.2` below are kept for the record only, and nothing should resolve
to them.

### Breaking — request

- `Posto.register(platformId:)` → `Posto.register(platformId:placementId:)`. The
  backend keeps two identifiers: `platformId` is the app (`X-Posto-Platform`,
  attestation `platform_id`, App Attest key-store scope) and `placementId` is the
  slot to fill, sent as `placement_id` in the body. It must belong to that app or
  the backend answers `400 invalid_placement`.
- `Posto.register(attestation:)` and `PostoAttestation` are **removed**. There is
  one lane and it is attested.
- **The unattested legacy lane is deleted** — `LegacyTransport`,
  `POST /v1/nativefeed/request`, GET impression beacons and click-through on
  `ad.url`. The new response carries no `url` and no beacons, so the lane had
  nothing left to run on. Devices that cannot attest throw
  `PostoError.backendRelayRequired`, as they already did.
- `AdContext(question:answer:image:user:commerce:)` →
  `AdContext(messages:user:)`, carrying up to three raw exchanges as
  `[AdMessage]`. `AdCommerce` is removed: category, offer type, location, price
  and other hard constraints are extracted from the person's own words, so there
  is nothing for the host app to declare.
- `AdUser(city:ageRange:country:)` → `AdUser(ageRange:gender:location:)`.
  `ageRange` and `gender` are closed enums and geography moves to `AdLocation`;
  the type no longer has a field in which GPS, a postal code or a street address
  could be sent.
- `requestAd` gained `format:`, defaulting to `.nativeCard`.

### Breaking — response

- `Ad.title` → `Ad.headline`. `Ad.body`, `Ad.imageAltText` and `Ad.requestID` are
  new; `image_alt_text` falls back to the headline rather than leaving a creative
  unlabeled.
- `Ad.format` is now `AdFormat` — a `RawRepresentable` wrapper, not an enum, so a
  format introduced after an SDK build still decodes.
- **Removed:** `Ad.product`, `Ad.uid`, `Ad.matchScore`, `Ad.url`, `Ad.productURL`,
  and the `ads` array. `AdTracking` lost `impressionURL`, `clickURL`,
  `impressionAPI` and `clickAPI`, and is no longer public API — it moved behind
  `@_spi(PostoInternal)`.
- The advertiser's URL is never sent to the device. `clickURL()` resolves the
  destination through the signed click event, so an ad cannot be navigated to
  without the click being reported, and an unbound `Ad` now throws rather than
  returning a fabricated URL.
- A `native_card` with no usable `image_url` is rejected at decode. Billing an
  impression for an ad the reader cannot act on is worse than a no-fill.

### Added

- **On-device contract validation** (`ContextValidator`). Messages must be
  chronological, start with the person and strictly alternate; conversations
  longer than three exchanges are **trimmed silently** to the most recent
  complete ones, while oversized (>4,000 bytes per message, >16,000 total) or
  malformed input **throws rather than being truncated**. A violation costs no
  network round-trip and names the field path that failed.
- `PostoError.invalidContext(String)`, raised both on-device and from the
  server's `422` — which previously fell through to `.unexpectedStatus(422)`
  despite the spec calling for a typed error. It carries the server's field path
  when one is sent.
- `AdDisclosure.sponsoredLabel(for:)` — the required "Sponsored" disclosure, in
  18 languages. Fixed in the SDK rather than transmitted per response, since it
  never varies by campaign.
- `@_exported import PostoCore` in the `Posto` module. The README has always told
  integrators to import only `Posto`, but a Swift module does not re-export its
  dependencies, so naming `AdContext`, `PiiFilter` or `PostoError` actually
  required a second `import PostoCore`. The documented surface is now the real
  one. SPI symbols are unaffected — the tracking tokens still need an explicit
  `@_spi` import.
- **Shared JSON contract fixtures** in `Tests/Fixtures/contract/` — request
  encoding, request rejections and response decoding. These are the cases every
  Posto SDK is checked against, not Swift test data; the Swift suite reads them
  rather than restating them, so a case fixed in one language cannot silently
  diverge from another.

### Changed

- The request body is a **closed schema** — `placement_id`, `format`, `context`,
  plus the optional `tracking_level` (omitted when 0) and `first_party_session_id`
  (omitted without a persistent user id) that the backend's decoder accepts; any
  other top-level key is a `422`. The SDK build travels as `X-Posto-Sdk-*` /
  `X-Posto-App-*` headers.
- The PII filter now covers every message, closing the gap where four of
  GUIDELINES §7's six filtered fields had no Swift representation. Redaction runs
  before the byte ceilings are enforced, so a message that only fits once its PII
  is replaced by placeholders is sendable.

### Known limitations

- The App Attest request path has been validated against Apple's implementation
  on a physical iPhone. CI still exercises a stub because
  `DCAppAttestService.isSupported` is false on every simulator, so every host app
  must run its own attested request → impression → click verification against
  `https://simulation.postoconnect.com` before release.
- **Headers are outside the signed canonical bytes.** The signature covers method,
  path, timestamp, idempotency key and the body hash. Only build metadata rides
  in headers; the tracking level and user id stay in the body, under the
  signature. Nothing security-bearing may move to a header.
- See `docs/ios-app-attest-follow-ups.md` for the remaining recovery gaps
  (`409 request_in_progress`, challenge expiry, clock skew, `app_version_too_old`).

## 2.0.0-beta.2

- Stop distributing the internal SDK handoff kit. `posto-ios-sdk-kit/` held the spec,
  guidelines and PII fixtures used to *build* this package — not something integrators
  should receive. SPM clones the whole repository, so every consumer was downloading it,
  backend implementation details included. It is now untracked and gitignored.
- The fixtures the package's own verification needs (`pii-corpus.json` and the two eval
  baselines) moved to `Tests/Fixtures/`, so `swift test` and `PostoPIIEval` are
  self-contained. Point `PostoPIIEval --kit <dir>` at a kit checkout for the full
  139-case eval dataset.

## 2.0.0-beta.1

**Prerelease.** The App Attest lane has not yet been exercised against physical
hardware — `DCAppAttestService.isSupported` is false on every simulator, so CI
verifies it only against a stub. Pin this version explicitly (`exact:`) and verify on
a device before adopting it in production. SPM excludes prereleases from `from:`
resolution, so 1.x integrators are unaffected.

### Breaking

- `Ad.trackImpression()` and `Posto.presentClick(_:from:)` are now `async throws` on
  **both** lanes. The attested lane cannot satisfy the old synchronous,
  fire-and-forget shape: generating a device assertion is async, and the click
  destination is not known until the server returns it.
- `Ad.impressionURL` moved to `Ad.tracking.impressionURL`. `Ad.tracking` also carries
  `clickURL`, `impressionToken`, `clickToken`, `impressionAPI`, `clickAPI`.
- `Ad` no longer stores an `HTTPClient`.
- `NativeFeed.init` no longer takes `platformId:` or `baseURL:` — the transport owns
  them. It now takes `transport:`.
- Legacy `trackImpression()` now surfaces errors instead of silently swallowing them,
  matching the attested lane. A failing beacon that used to be invisible will now
  throw.

### Added

- **App Attest lane.** `Posto.register(platformId:trackingLevel:baseURL:piiFilter:attestation:)`
  takes `attestation: .disabled` (default) or `.appAttest`. The attested lane signs
  every request with a device-bound assertion and uses `POST /v1/ads/request` plus
  `POST /v1/events/impression|click`; the legacy lane keeps
  `POST /v1/nativefeed/request` and GET beacons.

  Legacy is migration-only: not billable under production enforcement, and it returns
  `410 authenticated_ad_request_required` once enforcement is on.

  On a device that cannot attest, requests throw `PostoError.backendRelayRequired`.
  The SDK never falls back to an unsigned request — route those installs through your
  backend relay.

- **Device-side PII filter** (GUIDELINES §7), on by default. `piiFilter:` takes
  `.standard` (nine deterministic rules, the default), `.enhanced` (adds
  `NSDataDetector`/`NLTagger` name and address detection), or `.off`. Redaction runs
  before serialization on both lanes, so the bytes that get signed are the redacted
  bytes.

- New `PostoError` cases: `rateLimited(retryAfter:)`, `attestationUnavailable`,
  `backendRelayRequired`, `integrityRejected(String)`, `authenticatedRequestRequired`,
  `noRegisteredKey`, `malformedResponse(String)`.

### Changed

- **One status→error mapping shared by both lanes**, keyed by the server's error code
  where it matters: `401 invalid_platform` → `.invalidPlatform`, other `401`/`403`/`409`
  → `.integrityRejected`, `400` → `.badRequest(code)`, `410` →
  `.authenticatedRequestRequired`, `429` → `.rateLimited`, `503 attestation_unavailable`
  → `.attestationUnavailable`. Host error handling is now identical across lanes.
- Both lanes honor `Retry-After` (read case-insensitively — HTTP/2 lowercases header
  names on the wire).
- `HTTPResponse` gained `headers` and a case-insensitive `header(_:)` accessor.

### Known limitations

- The DeviceCheck path is unverified on hardware — see the prerelease note above.
- `AdContext` still lacks `commerce`/`user`/`interaction`, so four of GUIDELINES §7's
  six filtered fields have no Swift representation, and the `user.age_range`/`country`
  traits that drive audience matching cannot be sent.
- See `docs/ios-app-attest-follow-ups.md` for the full list, including four known
  recovery gaps (`409 request_in_progress`, challenge expiry, clock skew,
  `app_version_too_old`).

## 1.1.0

- Keychain accessibility fixed (`kSecAttrAccessibleAfterFirstUnlock`).
- `requestAd` before `register` throws `PostoError.notRegistered` instead of crashing.

## 1.0.0

- Initial release.
