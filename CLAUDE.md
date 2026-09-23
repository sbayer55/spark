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
- Dependencies via SPM declared in `project.yml`. Current: `sindresorhus/KeyboardShortcuts`.
- App Sandbox is on (with outgoing network client). `LSUIElement` is on (no Dock icon).
- Chat state is in memory only (no persistence yet).

## Build
```bash
xcodegen generate && xcodebuild -scheme Spark -destination 'platform=macOS' build
```
**A task isn't done until this build passes with no errors or warnings.**

## Layout
- `Spark/App`: `@main` app (MenuBarExtra + Settings scenes), AppDelegate, hotkey names
- `Spark/Panel`: `ChatPanel` (NSPanel subclass), `PanelController` (show/hide/position/resize), metrics
- `Spark/Chat`: `ChatViewModel` and SwiftUI views
- `Spark/Providers`: `LLMProvider` protocol, `MockProvider`, `ProviderRegistry` (TODOs mark where real clients go)
- `Spark/Models`: `ChatMessage`
- `Spark/Settings`: Settings window
- `Spark/Resources`: assets; `Info.plist` and entitlements are generated from `project.yml`
