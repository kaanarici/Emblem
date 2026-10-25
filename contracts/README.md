# Emblem server contract

The iOS app and the server deploy together. This file and `fixtures/` are the contract between them. The fixtures are written by the server's own code paths (`cd server && npm run contracts`), and `server/tests/contractFixtures.test.ts` fails when they are stale or no longer validate against the server's schemas. The app decodes every fixture with its real decoders.

All endpoints take `Authorization: Bearer <Clerk JWT>`. Times are Unix milliseconds. Cursors are opaque strings: send back exactly what the server returned and never build one.

## Conversation

```ts
type Conversation = {
  key: string;
  title: string;
  updatedAt: number;
  archived: boolean;
  pinnedAt?: number;
  preview: string | null;
  image?: {
    query: string;
    kind: "photo" | "poster" | "still";
    aspect?: "square" | "portrait" | "landscape";
  };
  imageURL?: string;
};
```

- `title` is the person's own title when they renamed the conversation, otherwise the model's title for the newest page.
- `updatedAt` is when the newest top-level page was requested. Expansion pages do not move it.
- Pin, archive and a custom title belong to the person. Generating, refreshing a summary, saving a writing draft and changing artwork never clear them.

## `GET /api/conversations`

Query: `cursor` (optional), `limit` (optional, 1 to 100, default 50), `archived` (optional, `true` for the Archived list).

```ts
{ pinned: Conversation[]; conversations: Conversation[]; nextCursor: string | null }
```

- Default list (no `archived`): only unarchived conversations. `pinned` comes first and holds the pinned ones, newest pin first. `conversations` holds the unpinned ones, newest `updatedAt` first. A conversation is in exactly one of the two arrays.
- All pinned conversations arrive before any unpinned one. Up to 100 pinned come per response, so for nearly everyone they all arrive on the first page with the first unpinned page. Past 100 pins, the next pages continue `pinned` with `conversations: []` until the pins run out. Append both arrays as pages arrive.
- `archived=true`: archived conversations, pinned or not, newest `updatedAt` first, all in `conversations`; `pinned` is always `[]`.
- `nextCursor` is `null` on the last page. A cursor carries its own list, so `archived` is read only on the first request. A malformed cursor returns `400 { error, code: "invalid_cursor" }`.
- A response can hold fewer than `limit` items while `nextCursor` is still set. Stop only on `null`.
- Guests get `{ pinned: [], conversations: [], nextCursor: null }`.
- Pages are not a snapshot. A conversation updated between requests can appear twice or move; key items by `key`, keeping the newest copy. Reload from the first page after a change.

Fixtures: `conversations-first.json`, `conversations-next.json`, `conversations-archived.json`.

## `GET /api/history`

Query: `conversationKey` (required), `cursor` (optional), `limit` (optional, 1 to 50, default 20).

```ts
{
  pages: {
    pageKey: string;
    previousPageKey?: string;
    parentPageKey?: string;
    sourceCardKey?: string;
    prompt: string;
    title?: string;
    blocks: Block[];
    activities: Activity[];
    sources: Source[];
  }[];
  nextCursor: string | null;
}
```

- The first request returns the newest pages of the conversation. `nextCursor` returns the pages just before them. Within a response, `pages` are in request order, oldest first, so the app prepends each later response.
- The order is by when each page was requested, which always puts a page after its `previousPageKey` and `parentPageKey`.
- `nextCursor` is `null` once the oldest page has been returned. A response can hold fewer than `limit` pages (large pages end a response early).
- Missing `conversationKey`: `400`. Unknown conversation or guest: `{ pages: [], nextCursor: null }`.

Fixtures: `history-first.json`, `history-next.json`.

## `POST /api/conversation`

Body: `{ action: "pin" | "unpin" | "archive" | "unarchive" | "rename" | "delete", conversationKey: string, title?: string }`.

- `pin`, `unpin`, `archive`, `unarchive` and `rename` are one write: `{ ok: true, action }`, or `404` when the conversation has no summary yet. `rename` needs a non-empty `title` (trimmed, at most 120 characters stored).
- `delete` erases every page, generation record and summary of the conversation, cancelling a running generation. It returns `{ ok: true, action, count }`. When it cannot finish in one request it returns `503 { ok: false, retryable: true, code: "conversation_incomplete" }`; send the same request again.

## `POST /api/home`

Body (JSON, every field optional): `{ name?: string, timezone?: string, nextEventTitle?: string, nextEventStart?: string | number }`. `nextEventStart` is Unix seconds. The person's name and calendar event title travel only in the body, never in the URL, so access logs and caches never hold them.

The response is the generate stream format: one `pageSnapshot` and a `terminal`. A body that is not this object returns `400`. Guests get the same page without the daily-update blocks.

## `POST /api/generate` stream

NDJSON, one event per line, escaped through the server's `ndjsonLine`. Events: `status`, `pagePreview`, `pageSnapshot`, `activity`, `sources`, `metric`, `inference`, `error`, `terminal`. Snapshot revisions only increase. `terminal` comes last, and for `completed` its `revision` and `blockCount` match the last snapshot.

Fixtures:

- `generate-completed.ndjson`: a signed-in page with status, preview, snapshot, activity, sources, metric and terminal.
- `generate-guest.ndjson`: a guest page; `terminal` has no `persisted`.
- `generate-failed.ndjson` and `generate-cancelled.ndjson`: an emptied preview, the error, then `terminal`.
- `generate-replay.ndjson`: a repeated request ID replaying its stored page (`X-Emblem-Replayed: 1`).
- `generate-guest-limited.ndjson`: a refusal before any work, here the guest limit.

## Other fixtures

- `home.ndjson`: `POST /api/home` with a name and a next event, a snapshot and terminal in the generate stream format.
- `blocks.json`: every block type the server can emit, built from `server/lib/schema.ts` with every optional field filled. A block type appears more than once when needed so that every enum value, union branch and action destination appears at least once.
