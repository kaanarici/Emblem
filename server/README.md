# Emblem server

The API for the Emblem iPhone app. Next.js route handlers own authentication, model calls, research and response validation. Convex owns persisted records, generation leases, ownership checks and scheduled work.

## Check it

Use Node.js 22 or later.

```sh
npm ci
npm run check
```

`npm run check` runs the type checker, ESLint, the no-comments and file-length checks, knip, Prettier, every test and a production build. While iterating, `npm run check:fast` type-checks the tree and runs the other checks and the related tests on files changed since `origin/main`.

## Run it

1. Copy `.env.example` to `.env.local`.
2. Run `npx convex dev` and leave it running. It creates a development deployment, writes `NEXT_PUBLIC_CONVEX_URL` to `.env.local` and keeps the functions in `convex/` deployed.
3. Give Next.js and Convex the same rate-limit secret. Every paid route refuses requests without it, guests included:

   ```sh
   SECRET=$(openssl rand -hex 32)
   echo "RATE_LIMIT_SECRET=$SECRET" >> .env.local
   npx convex env set RATE_LIMIT_SECRET "$SECRET"
   ```

4. Add a model key. The default provider is Cerebras and needs `CEREBRAS_API_KEY`. See [Models](#models) for the others. `EXA_API_KEY` turns on web search; research works without it.
5. Run `npm run dev`, then ask for a page as a guest:

   ```sh
   curl -N localhost:3000/api/generate -H 'content-type: application/json' \
     -d '{"messages":[{"role":"user","content":"How tall is Mount Everest?"}]}'
   ```

   The response is newline-delimited JSON: `status` lines while it works, one `pageSnapshot` with the page's blocks, `activity` and `sources` lines when research used tools, a timing `metric`, and a closing `terminal` line.

Signed-in requests also need Clerk: `CLERK_JWT_KEY` or `CLERK_SECRET_KEY` in `.env.local`, and `CLERK_JWT_ISSUER_DOMAIN` on the Convex deployment. The other variables in `.env.example` and `convex.env.example` turn on optional features. On startup, `lib/env.ts` logs each missing one and what stops working without it.

## Authentication

Every request carries its own credentials. There is no cookie or session.

- A signed-in request sends `Authorization: Bearer <token>`, using the Clerk JWT template named `convex`. The server requires the `convex` audience. The owner comes from the token's issuer and subject, never from a request field.
- A request with no `Authorization` header is a guest. Guests can generate pages, but nothing is stored, and history routes return empty lists.
- An invalid, expired or wrong-audience token gets 401 `invalid_auth`. It never falls back to guest. Missing auth configuration gets 503 `auth_unavailable`.

## Models

`LLM_PROVIDER` picks the research model. Composition runs on the same model when the provider is `openai` or `openrouter`, and on Cerebras otherwise, unless `LLM_COMPOSE_MODEL` says otherwise.

| `LLM_PROVIDER`       | Default model                               | Keys needed                                               |
| -------------------- | ------------------------------------------- | --------------------------------------------------------- |
| `cerebras` (default) | `qwen-3.8-27b`                              | `CEREBRAS_API_KEY`                                        |
| `openai`             | `gpt-6-luna`, Responses API, `store: false` | `OPENAI_API_KEY`                                          |
| `google`             | `gemini-3.5-flash-lite`                     | `GEMINI_API_KEY`, plus `CEREBRAS_API_KEY` for composition |
| `groq`               | `openai/gpt-oss-120b`                       | `GROQ_API_KEY`, plus `CEREBRAS_API_KEY` for composition   |
| `openrouter`         | `openai/gpt-6-luna`                         | `OPENROUTER_API_KEY`                                      |

`LLM_MODEL` overrides the research model. With `openrouter` it takes any OpenRouter model ID that supports tool calling and JSON output, such as `anthropic/claude-haiku-5.5`, `google/gemini-3.5-flash-lite`, `deepseek/deepseek-v4.1-flash` or `mistralai/mistral-large-4-0`. `LLM_COMPOSE_MODEL` sets composition to `google:<model>`, `openai:<model>`, `openrouter:<model>` or a bare Cerebras model ID. `OPENAI_REASONING_EFFORT` is one of `none` (the default), `minimal`, `low`, `medium`, `high`, `xhigh` or `max`. `lib/provider.ts` resolves the profile.

The app can also pick a model per request:

- `x-emblem-managed-model` names an OpenRouter model run on the server's `OPENROUTER_API_KEY`: `inception/mercury-3` or `openai/gpt-6-luna`.
- A signed-in user can bring their own Cerebras, OpenAI or OpenRouter key with `x-emblem-inference-provider`, `x-emblem-inference-key` and `x-emblem-inference-model`.

Either way, research and composition both run on that model.

Composition asks for strict JSON schema output, and the server still validates every block. Providers limit schemas differently (`lib/provider.ts`):

- **Cerebras** caps the total length of property names, definition names and enum values at 5,000 characters and counts a shared definition at every use. Image and icon fields use a compact grammar that the server expands. `tests/providerSchemaLimits.test.ts` fails if the schema comes within 250 characters of the cap.
- **OpenAI** allows 120,000 characters but requires every property to be required. Optional properties are sent as nullable, and nulls are dropped before validation. The same test checks OpenAI's limits.
- **Google** gets the block catalog in the prompt.
- **OpenRouter** sends the OpenAI form of the schema to every model. Some hosts refuse it (Anthropic allows 16 nullable fields, Gemini rejects the size), and some cannot turn reasoning off. On that 400 the server retries once without what was refused, using JSON mode with the schema in the prompt, and remembers the model until restart.

## Request lifecycle

`POST /api/generate` streams newline-delimited JSON, one event per line.

1. The route authenticates the caller, checks any automation execution grant against the live run in Convex (`lib/generationRequest.ts`) and admits guests against their budget. Only then is the body read, under a size limit (`lib/http.ts`).
2. Signed-in requests claim a `generationRuns` lease (`convex/pages.ts`). A repeated request ID replays the stored page or is rejected. It never runs the model twice.
3. `lib/generationStream.ts` runs the generation:
   - **Research** (`lib/research.ts`) calls tools: web search, weather, places, connected apps, memory, and Nuitée sandbox hotels and flights. Results collect in one `GenerationEvidence` (`lib/generationEvidence.ts`).
   - **Composition** (`lib/generationCompose.ts`) asks the model for typed blocks, with one retry. `lib/schema.ts` is the block contract the app decodes; `npm run contracts` writes every block type and payload to `contracts/fixtures`, which the app's tests decode. `lib/composerSchema.ts` derives the model-facing schema. `lib/pageAssembly.ts` drops map places and links that research never returned.
   - Hotel results reach the model as a compact projection with at most eight rooms and short `hotel:<id>` image references that the server expands.
   - If composition fails mid-stream, the retry continues from the valid blocks already parsed. If a page hits the output cap and still cannot finish, its valid prefix (page metadata plus at least two content blocks) is published.
   - **Publishing** resolves music, links and artwork (`lib/imageResolve.ts`), saves the page under the lease, and emits one final `pageSnapshot` and a `terminal` event (`lib/generationEvents.ts`).
4. Clients that send `X-Emblem-Preview: v1` also get provisional `pagePreview` events while the model streams. The app sends it.

`lib/generationProtocol.ts` defines every event. Every line goes through `ndjsonLine`, which escapes U+0085, U+2028 and U+2029 because Swift line readers treat them as line breaks.

## Automations

`convex/background.ts` keeps one wakeup scheduled for the next due automation or lease expiry, and a five-minute cron restarts the chain if a wakeup is lost. A due automation becomes an `automationRuns` row with a lease. Each wakeup claims at most 10 runs, with at most 100 queued or running at once (`convex/automationDispatch.ts`). A full batch schedules the next wakeup two seconds later; other backlog retries after a minute. `convex/automationExecution.ts` calls `/api/generate` with a signed grant bound to the run and lease, and the route refuses it unless Convex confirms the lease is live. The app manages automations through `/api/agents`.

## Data ownership

Every Convex function takes the owner from `ctx.auth` (`convex/ownership.ts`), never from arguments. Account deletion (`convex/accounts.ts`) first writes an erasure fence (`ownerErasures`), then drains one owned table per transaction, at most 80 rows and 1 MiB of reads each. It deletes the user record only after every owned table is empty. Writes for a fenced owner are rejected.

## Limits

- Every route that spends provider credit goes through `METERED_ROUTES` in `lib/meteredAccess.ts`: a budget per signed-in user or guest address, plus one shared cap across guests on guest routes.
- Budgets use the [Convex Rate Limiter component](https://www.convex.dev/components/rate-limiter), pinned to 0.3.2 because 0.4.2 needs Convex 1.43. `lib/rateLimitGrant.ts` signs short reservations bound to the owner or guest; the public mutation accepts only those. Bucket keys are HMAC-derived, so addresses and identities are not stored. Guests are keyed by `X-Real-IP`, which the platform in front of Next.js must set and overwrite; requests without it share one bucket.
- Paid image generation also passes `imageGenerationAdmission`: one attempt per image an hour, and a server-wide bucket of `IMAGE_GENERATIONS_PER_DAY` (default 300) that refills over 24 hours. Cache hits spend nothing. Past the ceiling, icons fall back to SF Symbols and steps show no illustration.
- Image routes reserve up to eight permits at once, valid for one second; other routes reserve one. Unused permits are discarded, not refunded. Outages refuse requests. Rotating `RATE_LIMIT_SECRET` starts fresh budgets.
- Clearing memory deletes at most 80 records per batch, up to 100 batches or ten seconds.
- Resolved image URLs and generation runs are kept for 30 days, then purged by daily crons. A request ID replayed after that runs again.
- Errors are logged as one JSON line each (`lib/log.ts`) with the error's name, code and status, never its message or stack. Each event is capped at 20 lines a minute.
- Connected apps use Composio and are read-only. Every result passes through the allowlisted projection in `lib/connectorPresentation.ts`, before the model sees it and before `GET /api/calendar/events` returns it. That route gives the app a signed-in person's Google Calendar events between `start` and `end` (ISO 8601 instants at most 45 days apart, plus an optional `timeZone`), read per connected account: an account that fails is marked `failed` and the others still return. Guests and people without a connection get `notConnected` and no events. It has its own small budget in `METERED_ROUTES`.

## Deploying

Deploy the Next.js app as a standard Next.js app, for example on Vercel. Long-running routes set their own `maxDuration`. Deploy the Convex functions with `npx convex deploy`.

- Next.js needs `NEXT_PUBLIC_CONVEX_URL`, a Clerk key, `RATE_LIMIT_SECRET`, the keys for your model profile, `GENERATED_STEP_IMAGE_TOKEN_SECRET`, `GENERATED_STEP_IMAGE_STORAGE_SECRET` and `AUTOMATION_SERVICE_KEY`.
- Convex needs the variables in `convex.env.example`: `CLERK_JWT_ISSUER_DOMAIN`, `GENERATE_ORIGIN` (the public origin of the Next.js app, used by automations), and the same `AUTOMATION_SERVICE_KEY`, `GENERATED_STEP_IMAGE_STORAGE_SECRET` and `RATE_LIMIT_SECRET`.
- `convex/crons.ts` runs the five-minute wakeup recovery and reservation cleanup, the 04:00 UTC image-cache purge and the 04:30 UTC generation-run purge.
- Ship Next.js and Convex changes together. They share execution grants, rate-limit reservations and automation errors.
