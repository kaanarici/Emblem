# Contributing

## Server

```sh
cd server
npm ci
npm run check:fast
```

`npm run check:fast` type-checks the tree and runs ESLint, the no-comments and file-length checks, knip, Prettier and the related tests on files changed since `origin/main`. Run it while you work.

`npm run check` is the full gate: the same checks on the whole tree, every test and a production build. A change is ready when it passes.

- Server source files have no comments. Explain non-obvious behaviour in a README or a test name.
- Format with `npm run format`.
- Tests guard contracts a change could break silently: authentication and ownership, erasure, connector data projection, signed grants, metered spend and the generation protocol shared with iOS. Test at the route or Convex boundary. Don't add tests that pin prompts, layouts or internal plumbing.
- Convex functions take the owner from `ctx.auth`, never from arguments.

## iOS

Run `ios/generate-project.sh` after changing `ios/project.yml`. Keep debug and QA hooks inside `#if DEBUG`.

```sh
scripts/ios-check.sh
```

It runs the swift-format rules and the file-length check, builds the app for a Simulator, then runs `EmblemGenerationTests` on macOS and `EmblemRecordingTests` on the Simulator. `--journeys` adds the `EmblemUITests` journeys.

`EmblemGenerationTests` covers the generation stream, authenticated transport and per-account conversation caches. `EmblemRecordingTests` checks that Apple-model pages never go to the server for voice or writing rewrites.

## Pull requests

Keep each pull request to one change. Say what behaviour it changes and how you checked it.
