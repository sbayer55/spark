# Spark

Native macOS menu bar app for quick AI chats across multiple LLM providers (Ollama, Bifrost, 9router, Anthropic).

## Rules
- **Swift 6** with complete strict concurrency. No warnings allowed.
- **macOS 26 (Tahoe) minimum.** No `#available` fallbacks or code paths for older macOS.
- **SwiftUI-first.** Use AppKit only where SwiftUI can't do the job (currently: the floating `NSPanel` in `Spark/Panel/`).
- **Observation framework** (`@Observable`, `@Bindable`). Never `ObservableObject` / `@Published`.
- **Liquid Glass** via `.glassEffect(...)` and `GlassEffectContainer`. Do not substitute `NSVisualEffectView` or materials.
  Liquid Glass APIs are newer than much training data: check Apple's docs (or the SDK's `.swiftinterface`) instead of guessing signatures.
- **XcodeGen only.** The project is defined in `project.yml`; `*.xcodeproj` is generated and gitignored. Never hand-edit it.
  Add files by placing them under `Spark/`; add settings, entitlements, Info.plist keys, and SPM packages in `project.yml`.
- **Writing Tools is disabled app-wide.** There's no global switch, so every window's root view applies
  `.writingToolsBehavior(.disabled)` (currently `ChatView` and `SettingsView`). New windows must do the same.
- Dependencies via SPM declared in `project.yml`. Current: `sindresorhus/KeyboardShortcuts`, `swiftlang/swift-markdown`,
  `scinfu/SwiftSoup` (only `Spark/Research/PageReader.swift` may `import SwiftSoup`).
- App Sandbox is on (with outgoing network client). `LSUIElement` is on (no Dock icon).
- Chat state is in memory only (no persistence yet). Several chats can be open at once (⌘N new, ⌘W close,
  ⌃Tab switcher); a background chat keeps streaming. A closed panel keeps its chats for the "Keep chat after closing"
  setting (`ChatRetention`, default 5 minutes); reopening after that drops every chat not mid-reply and starts a new one.
  Settings (Ollama URL, last-picked model, retention, panel size, text size) live in `UserDefaults`.
  The Brave Search API key lives in the Keychain (`Keychain.swift`, mirrored by `BraveSearchKey`), never in `UserDefaults`.
- **Research mode** (composer toggle) runs `ResearchAgent` on top of the plain text-streaming provider interface:
  plan queries (prompt-and-parse JSON) → Brave Search → read pages → optional follow-up round → cited answer.
  Progress is reported as `ResearchEvent`s into the assistant `ChatMessage.research` state. No tool calling is used.
- ATS allows plain HTTP only to local hosts (`NSAllowsLocalNetworking`).

## Build
```bash
xcodegen generate && xcodebuild -scheme Spark -destination 'platform=macOS' build
```
**A task isn't done until this build passes with no errors or warnings.**

## Layout
- `Spark/App`: `@main` app (MenuBarExtra + Settings scenes), AppDelegate, hotkey names
- `Spark/Panel`: `ChatPanel` (NSPanel subclass), `PanelController` (show/hide/position/resize), metrics
- `Spark/Chat`: `ChatStore` (open chats in most-recently-used order, ⌃Tab switcher state), `ChatViewModel` (one chat),
  and SwiftUI views. Panel keys (⌃Tab, ⌘N, ⌘W, Escape) are routed in `PanelController` via `ChatPanel`.
- `Spark/Chat/Markdown`: markdown parsing (`MarkdownParser`, swift-markdown) and rendering (`MarkdownView`).
  Only `MarkdownParser.swift` may `import Markdown`; its `Text`/`Link`/`Image`/`Table` types clash with SwiftUI.
- `Spark/Providers`: `LLMProvider` protocol, `OpenAICompatibleProvider` (SSE client; Ollama uses it via `Ollama.swift`),
  `MockProvider` (Anthropic/Bifrost/9router until real clients land; see TODOs), `ProviderRegistry` (live model lists)
- `Spark/Models`: `ChatMessage`, `Research` (research steps, sources, events)
- `Spark/Research`: `ResearchAgent` (orchestration), `ResearchPrompts`, `BraveSearchClient`, `PageReader` (SwiftSoup),
  `BraveSearchKey` (Keychain-backed key store)
- `Spark/Settings`: Settings window, `Keychain` helper
- `Spark/Resources`: assets; `Info.plist` and entitlements are generated from `project.yml`
