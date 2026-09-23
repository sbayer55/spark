# Spark

A macOS menu bar app for quick AI chats across multiple LLM providers. Press **Option+Space** anywhere to open a floating Liquid Glass chat panel.

> Status: scaffolding. Providers are mocked and stream canned responses; there are no network calls yet.

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
open build/Build/Products/Debug/Spark.app
```

Spark has no Dock icon. Look for the ✦ sparkle in the menu bar.

## Usage
- **Option+Space**: show/hide the chat panel (change it in Settings…)
- **Return**: send; **Shift+Return**: newline
- **Escape**: stop a streaming reply, or close the panel if nothing is streaming
- The model picker at the bottom-left of the composer switches provider and model
