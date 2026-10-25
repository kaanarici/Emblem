# Emblem

Emblem is an iPhone assistant that answers with a native, generated page instead of a chat bubble. `ios/` is the SwiftUI app. `server/` is a Next.js API plus a Convex backend. Next owns HTTP, auth, model and provider calls, and validation. Convex owns records, generation leases, ownership, schedules and the rate limiter. The app never talks to Convex directly.

## Request path

1. `ios/Emblem/UI/Dock/DockView.swift` hands the prompt to `ConversationStore`. `GenerationSession` owns one run and its retries; `GenerationLifecycle` decides which transitions are allowed. Both live in `ios/EmblemCore`.
2. `ios/EmblemCore/Sources/EmblemCore/Networking/GenerateClient.swift` POSTs with the Clerk bearer to `server/app/api/generate/route.ts`: auth (`lib/auth.ts`), service grant (`lib/generationRequest.ts`), spend limits (`lib/meteredAccess.ts`, `lib/rateLimit.ts`), then a lease (`convex/pages.ts`).
3. `lib/generationStream.ts` runs research (`lib/research.ts`), composition against the block contract (`lib/generationCompose.ts`, `lib/schema.ts`), grounding (`lib/pageAssembly.ts`) and artwork (`lib/imageResolve.ts`), persists the page, then emits `pageSnapshot` and `terminal` (`lib/generationEvents.ts`).
4. `EmblemCore/Generation/GenerationStream.swift` decodes the NDJSON into a `GeneratedPage`; `ios/Emblem/UI/Render/BlockView.swift` renders one view family per `Block` case (`EmblemCore/Blocks/Blocks.swift`).

Automations: `convex/background.ts` wakes due runs, and `convex/automationExecution.ts` calls `/api/generate` with a signed execution grant. Screen-to-owner map: `docs/architecture.md`. Server stages and limits: `server/README.md`.

## Invariants

- The owner comes only from `ctx.auth` (`convex/ownership.ts`), never from arguments. Guests have no durable namespace. Leases replay a request ID exactly once, and the erasure fence blocks writes after account deletion (`server/tests/ownership.test.ts`).
- Connector data reaches the model and pages only through the allowlisted projection in `lib/connectorPresentation.ts` (`server/tests/connectors.test.ts`). Prompt text is never the privacy boundary.
- Stream format: `lib/generationProtocol.ts` defines every event, and every line goes through `ndjsonLine`, which escapes U+0085, U+2028 and U+2029. Snapshot revisions only increase and terminal counts must match; the iOS decoder rejects anything else (`EmblemGenerationTests`). A block or payload change edits `lib/schema.ts` and `Blocks.swift` together, then reruns `cd server && npm run contracts`; `contracts/fixtures` are decoded by the app's tests (`contracts/README.md`).
- Spend: every paid route admits through `METERED_ROUTES` and the signed reservations in `lib/rateLimit.ts`. Admission fails closed without `RATE_LIMIT_SECRET`.
- Persisted transitions live in Convex and come with a contract test.
- Layering, enforced by ESLint: `convex/` imports only the `lib` modules listed in `convexSharedLib` (`server/eslint.config.mjs`); `lib/` never imports `app/` or a Convex module; `app/` reaches Convex only through `convex/_generated`.

## Code rules

- Make the smallest complete change in the existing owner. Delete superseded code; keep no shims for data that never shipped.
- No comments anywhere in the code. The server enforces it (`scripts/check-no-comments.mjs`); Swift and Metal follow the same rule.
- Server files stay under 500 lines, Swift files under 600. The baselines (`server/max-lines-baseline.json`, `ios/file-length-baseline.txt`) only shrink: split the file, never raise them.
- Tests protect behavior a person would notice or a contract across a boundary. No snapshot, mock-only or payload-reconstruction tests.
- Tappable cards and rows that open a page are buttons with the shared pressed style.

## Commands

- `cd server && npm run check:fast`: types, lint, Prettier, knip and `vitest related` on files changed since the merge base with `origin/main`. Run it while iterating.
- `cd server && npm run check`: the gate before landing. Everything above on the whole tree, all tests and `next build`.
- `cd server && npm run lint:ratchet`: lock in a smaller size after shrinking a file.
- `scripts/ios-check.sh`: swift-format rules, the file-length ratchet, a Simulator build, `EmblemGenerationTests` (macOS) and `EmblemRecordingTests`. `--journeys` adds the XCUITest journeys and `--ratchet` lowers the baseline. `EMBLEM_SIMULATOR` names the Simulator; it is created if missing.

## Verifying UI

- Drive the Simulator headless with `xcrun simctl` and XCUITest. No Simulator window is needed.
- A screenshot proves a change only if it comes from a fresh build of the current source, cold-launched (`simctl terminate`, then `simctl launch`) and allowed to settle. Capture the same state before and after the change with `xcrun simctl io <device> screenshot`.
- `ios/EmblemUITests` journeys run the app against `StubServer`, a loopback server that streams `ios/Emblem/Fixtures/*.json` through the real network, decoding and rendering path. Find elements by accessibility identifier and tap by coordinate (`JourneyTestCase.tap`); accessibility activation can succeed where a finger would miss.
- A change to a gesture-heavy surface (dock recording, carousels, sidebar, back navigation) reruns `scripts/ios-check.sh --journeys`.
