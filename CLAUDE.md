# Spark

Native macOS menu bar app for quick AI chats across multiple LLM providers (Ollama, Anthropic, Amazon Bedrock, Bifrost, 9router).

## Rules
- **Swift 6** with complete strict concurrency. No warnings allowed.
- **macOS 26 (Tahoe) minimum.** No `#available` fallbacks or code paths for older macOS.
- **SwiftUI-first.** Use AppKit only where SwiftUI can't do the job (currently: the floating `NSPanel` in `Spark/Panel/`,
  and the panel's behind-window blur).
- **Observation framework** (`@Observable`, `@Bindable`). Never `ObservableObject` / `@Published`.
- **The chat panel is flat**, not Liquid Glass: Liquid Glass always draws a lit rim, which the user doesn't want.
  `panelBackground(cornerRadius:)` (`PanelAppearance.swift`) is a behind-window `NSVisualEffectView` blur (masked to a
  rounded rect) under a theme-colored fill; the transparency and blur settings drive it. Use it for panel surfaces.
  The alternative "Gaussian" blur engine uses the private SkyLight `CGSSetWindowBackgroundBlurRadius` (looked up with
  `dlsym` in `Spark/Panel/SkyLight.swift`, the only place private API is allowed); the window server blurs behind every
  non-transparent pixel, so in that mode nothing may paint the panel window's transparent margin.
  Elsewhere prefer Liquid Glass (`.glassEffect(...)`); its APIs are newer than much training data, so check Apple's docs
  (or the SDK's `.swiftinterface`) instead of guessing signatures.
- **XcodeGen only.** The project is defined in `project.yml`; `*.xcodeproj` is generated and gitignored. Never hand-edit it.
  Add files by placing them under `Spark/`; add settings, entitlements, Info.plist keys, and SPM packages in `project.yml`.
- **Writing Tools is disabled app-wide.** There's no global switch, so every window's root view applies
  `.writingToolsBehavior(.disabled)` (currently `ChatView` and `SettingsView`). New windows must do the same.
- Dependencies via SPM declared in `project.yml`. Current: `sindresorhus/KeyboardShortcuts`, `swiftlang/swift-markdown`,
  `scinfu/SwiftSoup` (only `Spark/Research/PageReader.swift` may `import SwiftSoup`), `jpsim/Yams`
  (only `Spark/Providers/Import/DeepSeekHarnessConfig.swift` may `import Yams`).
- App Sandbox is on (with outgoing network client, and read-only access to files the user picks). `LSUIElement` is on (no Dock icon).
- Chat state is in memory only (no persistence yet). Several chats can be open at once (⌘N new, ⌘W close,
  ⌃Tab switcher); a background chat keeps streaming. A closed panel keeps its chats for the "Keep chat after closing"
  setting (`ChatRetention`, default 5 minutes); reopening after that drops every chat not mid-reply and starts a new one.
  Settings (Ollama URL, last-picked model, retention, system prompt, panel size, text size, theme, panel transparency
  and blur) live in `UserDefaults`. The system prompt (`SystemPrompt`) is read at each send; research uses it only
  for the final answer, since the planning prompts need their strict JSON instructions.
  The Brave Search API key lives in the Keychain (`Keychain.swift`, mirrored by `BraveSearchKey`), never in `UserDefaults`.
- **Anthropic and Amazon Bedrock** are native clients, listed only once their credentials are set in Settings.
  Anthropic: API key in the Keychain (`KeychainSecret`). Bedrock: region and sign-in method in `UserDefaults`,
  credentials (Bedrock API key, or IAM access key + optional session token) in one Keychain item (`BedrockSettings`).
  Bedrock uses the Converse API with our own SigV4 signer (`AWSSigV4`) and event-stream decoder (`AWSEventStream`);
  no AWS SDK.
- **Custom providers** (`CustomProviders`) are OpenAI-compatible endpoints imported in Settings from opencode
  (`opencode.json[c]`, `auth.json`), DeepSeek Harness (`~/.dsh`: `settings.yaml`, profile `cordis.patch.yml`,
  `.credentials.yaml`, `.env`), or 9router (`~/.9router`: SQLite `db/data.sqlite` or legacy `db.json`).
  The sandbox means the user picks the file/folder; configs go in `UserDefaults`, API keys in the Keychain.
  Anthropic-protocol entries are skipped (the importer only creates OpenAI-compatible providers).
- **Research mode** (composer toggle) runs `ResearchAgent` on top of the plain text-streaming provider interface:
  plan queries (prompt-and-parse JSON) → Brave Search → read pages → optional follow-up round → cited answer.
  Progress is reported as `ResearchEvent`s into the assistant `ChatMessage.research` state. No tool calling is used.
- ATS allows plain HTTP only to local hosts (`NSAllowsLocalNetworking`).

## Build
```bash
xcodegen generate && xcodebuild -scheme Spark -destination 'platform=macOS' build
```
**A task isn't done until this build passes with no errors or warnings.**

## Testing the running app
Launch arguments (`LaunchOptions`) make the app scriptable without touching the user's Keychain or settings:
```bash
open <DerivedData>/Build/Products/Debug/Spark.app --env SPARK_SECRET_ANTHROPIC_API_KEY=… \
  --args -SparkEphemeralSecrets YES -SparkShowPanelOnLaunch YES -themeID system
```
- `-SparkEphemeralSecrets YES` keeps secrets in memory (no Keychain prompts, which ad-hoc signing triggers on every
  rebuild). Seed them with `SPARK_SECRET_<ACCOUNT>` env vars (see `Keychain`). Automatic under XCTest.
- `-SparkShowPanelOnLaunch YES` opens the chat panel at launch; scripts can't press the global hotkey.
- Any setting can be overridden for one launch with `-<defaultsKey> <value>` (argument domain; not persisted).

## Layout
- `Spark/App`: `@main` app (MenuBarExtra + Settings scenes), AppDelegate, hotkey names
- `Spark/Panel`: `ChatPanel` (NSPanel subclass), `PanelController` (show/hide/position/resize), metrics
- `Spark/Chat`: `ChatStore` (open chats in most-recently-used order, ⌃Tab switcher state), `ChatViewModel` (one chat),
  and SwiftUI views. Panel keys (⌃Tab, ⌘N, ⌘W, Escape) are routed in `PanelController` via `ChatPanel`.
- `Spark/Chat/Markdown`: markdown parsing (`MarkdownParser`, swift-markdown) and rendering (`MarkdownView`).
  Only `MarkdownParser.swift` may `import Markdown`; its `Text`/`Link`/`Image`/`Table` types clash with SwiftUI.
- `Spark/Providers`: `LLMProvider` protocol, `OpenAICompatibleProvider` (SSE client; Ollama uses it via `Ollama.swift`),
  `AnthropicProvider` (Messages API), `ProviderHTTP` (shared error handling), `AlternatingTranscript` (system prompt +
  alternating turns for Anthropic/Bedrock), `MockProvider` (Bifrost/9router until real clients land; see TODOs),
  `ProviderRegistry` (live model lists), `CustomProviders` (user-added providers); `Bedrock/` holds the Bedrock client,
  settings, SigV4 signer, and event-stream decoder; `Import/` holds the per-tool config readers (`ProviderImporter` entry point)
- `Spark/Models`: `ChatMessage`, `Research` (research steps, sources, events)
- `Spark/Research`: `ResearchAgent` (orchestration), `ResearchPrompts`, `BraveSearchClient`, `PageReader` (SwiftSoup),
  `BraveSearchKey` (Keychain-backed key store)
- `Spark/Settings`: Settings window (General tab, Appearance tab with the `ThemePicker` grid), `Keychain` helper
- `Spark/Theme`: `Theme` (palette, `\.theme` environment, `Glass.themed`, `themeStyle`) and `ThemeCatalog` (built-in palettes).
  No theme (`Theme.systemID`) is the default Liquid Glass look; themed views must look right both ways.
- `Spark/Resources`: assets; `Info.plist` and entitlements are generated from `project.yml`
