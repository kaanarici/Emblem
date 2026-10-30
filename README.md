# Emblem

<p align="center">
  <img src="docs/media/hero.png" alt="Four iPhone screens: the Home greeting with recent chats and things to ask, a California road trip page with a route map, the map lens picking an area of New York, and the San Francisco weather with an hourly forecast" width="100%">
</p>

<p align="center"><b>Ask anything. Get a page, not a paragraph.</b></p>

Emblem is an iPhone assistant that answers with native pages. Ask about a trip and you get a map and a day-by-day plan. Ask for dinner and you get the recipe as step cards. Ask which of two things to pick and you get them side by side. It is written in SwiftUI and is open source.

## What it does

- **Answers become pages.** Maps, timelines, recipes, comparisons, charts, cards, quizzes and more. The server streams typed blocks and the phone draws each one natively as it arrives.
- **It asks before it guesses.** When a request is open-ended, a sheet of quick questions comes first.
- **Map lens.** Pick an area by moving the map under a glass lens.
- **Voice.** Hold the mic and a glass wave rises while you speak. Slide up to keep listening hands-free.
- **Calendar you can tap into.** Your iPhone calendar, Reminders and Google Calendar in one place, by day, week or month. It shows your free time, and every event opens into its own page with timing, a map and what to do next. Add events and to-dos from the dock.
- **Weather.** One card with the current conditions, the hours ahead and the week. Tap a day to see its hours.
- **Anodized themes.** Light or dark, with accent colors like Aluminum, Space Black, Blue and Purple.
- **Connectors.** Gmail and Google Calendar through Composio. Apple Calendar, Reminders and Apple Music on the phone.
- **Any model.** Any OpenRouter model with tool calling and structured outputs (tested with Claude, Gemini, DeepSeek, Mistral and GPT-6 Luna), Cerebras, OpenAI, Google or Groq. Or Apple Intelligence on the phone.
- **3D object icons and step illustrations.** Generated once with fal (or Gemini without a fal key), then cached.

<p align="center">
  <img src="docs/media/answers.png" alt="Four iPhone screens: a question sheet asking what kind of route sounds best, a chickpea curry recipe page, a Kyoto and Osaka comparison, and the same comparison opened full screen" width="100%">
</p>

<p align="center">
  <img src="docs/media/calendar.png" alt="Four iPhone screens: a calendar day with a to-do, free time and the evening's events, the week view, the month view, and the page for Dinner at Nopa" width="100%">
</p>

<p align="center">
  <img src="docs/media/app.png" alt="Three iPhone screens: the glass listening wave with a live transcript, the sidebar with search and pinned chats, and the accent color picker in Settings" width="100%">
</p>

## How it works

1. You ask by voice or text.
2. If the request is open-ended, the server sends back a few questions first.
3. **Research.** The model calls tools: web search, places, weather, hotels and your connected apps.
4. **Compose.** A second call writes the page as typed JSON blocks and streams them to the phone.
5. SwiftUI renders each block the moment it arrives. Photos and icons load alongside.

The app is SwiftUI with an `EmblemCore` Swift package for models, streaming and networking. The server is Next.js with Convex for data, scheduled pages and rate limits. [`docs/architecture.md`](docs/architecture.md) goes deeper.

## Services

Only Convex and one model provider are required. Everything else turns on when you add its key to `server/.env.local`.

| Service | Used for |
| --- | --- |
| [Convex](https://convex.dev) | Database, scheduled pages, rate limits (required) |
| Cerebras, OpenAI, Google, Groq, OpenRouter or ModelGo | The model (one is required) |
| [Exa](https://exa.ai) | Web search and photos |
| [Clerk](https://clerk.com) | Sign-in (otherwise everyone is a guest) |
| [Composio](https://composio.dev) | Gmail and Google Calendar |
| [fal](https://fal.ai) or Gemini | Generated 3D object icons and step illustrations |
| [LiteAPI](https://liteapi.travel) | Hotel search |
| TMDB and OMDb | Movie and TV posters |
| xAI | Spoken answers |
| Open-Meteo and Wikipedia | Weather and photos (free, no key) |

On the phone, Emblem uses Apple Intelligence (on device or Private Cloud Compute), EventKit for Calendar and Reminders, Apple Music and MapKit.

## Run it

You need a Mac with Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js 22+ and a Cerebras or OpenAI API key.

**1. Start the server**

```sh
cd server
npm ci
cp .env.example .env.local
npx convex dev
```

Leave `convex dev` running. It creates a Convex deployment and writes its URL to `.env.local`. In a second terminal, still in `server/`, share a rate-limit secret with Convex:

```sh
SECRET=$(openssl rand -hex 32)
echo "RATE_LIMIT_SECRET=$SECRET" >> .env.local
npx convex env set RATE_LIMIT_SECRET "$SECRET"
```

Add your model key to `.env.local`: `CEREBRAS_API_KEY`, or `LLM_PROVIDER=openai` with `OPENAI_API_KEY`. Then start the API on port 3000:

```sh
npm run dev
```

**2. Run the app**

```sh
cd ios
./generate-project.sh
open Emblem.xcodeproj
```

Pick an iPhone simulator, press Run, tap **Continue as guest** and ask anything.

**3. On your iPhone (optional)**

Copy `ios/Local.xcconfig.example` to `ios/Local.xcconfig` and set `EMBLEM_SERVER_URL` to an address your phone can reach. Then:

```sh
EMBLEM_DEVICE_BUNDLE_ID=com.you.emblem ios/run-device.sh
```

[`server/README.md`](server/README.md) lists every key and model option.

## Contributing

`cd server && npm run check:fast` checks the server files you changed. `scripts/ios-check.sh` lints the Swift code, builds the app and runs the iOS tests. See [CONTRIBUTING.md](CONTRIBUTING.md).

## How it was built

Emblem was built with Claude Code and Codex. It started as a project inspired by Monogram and is not affiliated with it.

## License

[AGPL-3.0](LICENSE). You can use, change and share Emblem, including commercially, as long as you release your full source under the same license. That also applies when you run a modified version as a hosted service or ship it in an app. Third-party notices are in [NOTICE](NOTICE).

The 3D object icons in my own build come from [Thiings](https://www.thiings.co), a licensed pack that is not included here. The build bundles it only when `EMBLEM_OBJECT_ASSET_DIR` points at a local copy. Without it, Emblem generates matching icons with fal or Gemini, and falls back to SF Symbols.

Dependencies keep their own licenses. `cd server && npm ls --omit=dev --all` lists the server's, and `ios/Package.resolved` pins the Swift packages.
