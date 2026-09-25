# Spark

A macOS menu bar app for quick AI chats across multiple LLM providers. Press **Option+Space** anywhere to open a floating Liquid Glass chat panel.

> Status: early. **Ollama** is live; Anthropic, Bifrost, and 9router are still mocked.

## Ollama
Install and start [Ollama](https://ollama.com), then pull a model:
```bash
ollama serve
```
```bash
ollama pull llama3.2
```
Spark lists your installed models under **Ollama** in the model picker. The server URL defaults to `http://localhost:11434` and can be changed in Settings….

## Requirements
- macOS 26 (Tahoe) or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Setup
```bash
brew install xcodegen
xcodegen generate
open Spark.xcodeproj
```
The Xcode project is generated from `project.yml` and isn't committed. Re-run `xcodegen generate` after pulling changes or adding files.

## Build & run
From Xcode: select the **Spark** scheme and press ⌘R.

From the command line:
```bash
xcodegen generate
xcodebuild -scheme Spark -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Spark.app --args -SparkEphemeralSecrets YES
```

Spark has no Dock icon. Look for the ✦ sparkle in the menu bar.

## CI & releases
- **CI** (`.github/workflows/ci.yml`) builds Debug and Release on every push to `main` and every PR, and fails if the build emits any warnings. It also runs a TruffleHog scan for leaked secrets in the pushed commits.
- **Release** (`.github/workflows/release.yml`) runs when you push a `v*` tag. It archives the app and attaches an ad-hoc-signed `Spark-<version>.zip` to a GitHub release. The tag has to match `CFBundleShortVersionString` in `project.yml` (for example, `v0.1.0`). The build isn't notarized, so on first launch, right-click the app and choose **Open**.
- **Dependabot** keeps the GitHub Actions versions up to date.

## Usage
- **Option+Space**: show/hide the chat panel (change it in Settings…)
- **Return**: send; **Shift+Return**: newline
- **Escape**: stop a streaming reply, or close the panel if nothing is streaming
- **⌘=** / **⌘-**: larger / smaller text; **⌘0**: reset text size
- The model picker at the bottom-left of the composer switches provider and model
- Closing the panel keeps your chat for 5 minutes; reopen after that and Spark starts a new chat.
  Change the limit (or keep chats until you start a new one) in Settings….
- Drag the panel's edges to resize it. It grows with the conversation until you change its height;
  after that it keeps your height. **Reset Panel Size** in the ✦ menu restores the default.
