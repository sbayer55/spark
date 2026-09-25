# Feature ideas

A running list of candidate features for Spark. Add ideas freely; promote the ones worth building to the
**Next up** section and move shipped ones to **Done** so the list stays honest.

Status keys: `idea` (unvetted), `next` (agreed, not started), `wip` (in progress), `done`.

## Next up

| Feature | Status | Notes |
| --- | --- | --- |
| Selected-text capture | idea | Second hotkey grabs the frontmost app's selection and opens the panel with it quoted. The core menu-bar-assistant workflow. |
| Image attachments | idea | Drag or paste an image into the composer. Anthropic, Bedrock Converse, and Ollama vision models all accept images. Needs content parts in `ChatMessage` and `AlternatingTranscript`. |

## Gaps in what exists

| Feature | Status | Notes |
| --- | --- | --- |
| Message hover actions | idea | Copy as markdown, copy code block, regenerate, edit-and-resend on `MessageRow`. |
| Export chat | idea | Copy whole thread or save as markdown. |

## New chat modes

`ChatMode` and the mode picker are built to grow.

| Feature | Status | Notes |
| --- | --- | --- |
| Rewrite / Fix mode | idea | Paste text, get an edited version back with copy or replace-selection. Pairs with selected-text capture. |
| Explain code mode | idea | Code-tuned system prompt; output already renders via `MarkdownView`. |
| Summarize URL mode | idea | Paste a link, `PageReader` fetches it, model summarizes. Research plumbing minus the search step. |
| Compare mode | idea | Same prompt to two models side by side. Multi-provider registry makes this cheap and it is a differentiator. |

## Input and output

| Feature | Status | Notes |
| --- | --- | --- |
| File and PDF attachments | idea | Sandbox-friendly via the file picker already used for provider imports. |
| Prompt library / snippets | idea | Slash commands in the composer (`/translate`, `/eli5`) expand to saved prompts editable in Settings. |
| Token and cost meter | idea | Show usage per reply from provider usage fields (Anthropic and Bedrock return them). |
| Voice input | idea | On-device speech recognition; natural for a hotkey-summoned panel. |

## Panel and macOS integration

| Feature | Status | Notes |
| --- | --- | --- |
| Pin / detach panel | idea | Keep the panel open across app switches, or pop a chat into a normal window. |
| Default model per mode | idea | E.g. cheap local model for Ask, a hosted model for Research. Also remember model per chat. |
| Shortcuts / App Intents | idea | "Ask Spark" from Shortcuts, Spotlight, and Siri. |
| Menu bar streaming indicator | idea | `StatusIcon` pulses while a background chat streams; badge when a reply finishes with the panel closed. |
| Source preview on hover | idea | Quick Look style preview of research sources. |

## Research mode

| Feature | Status | Notes |
| --- | --- | --- |
| Source pinning | idea | Let the user pin a fetched page as context and re-ask. |
| Local-folder research | idea | Same read-and-cite loop over user-picked folders, no Brave call. |
| Alternative search backends | idea | SearXNG, Kagi behind the same client interface. |

## Longer bets

| Feature | Status | Notes |
| --- | --- | --- |
| Tool calling | idea | Research intentionally avoids it today. Would let Ask mode use calculator, calendar, file lookups. Large change across three native clients. |
| MCP client support | idea | Use the same servers as the user's other tools. Heavy, but a real differentiator. |

## Done

| Feature | Shipped |
| --- | --- |
| Chat persistence: JSON history under Application Support, ⌘K search, open chats restored on relaunch | unreleased |
| Real Bifrost and 9router clients (OpenAI-compatible gateways, switched on in Settings) | unreleased |
| Multi-chat with ⌃Tab switcher | fa14e26 |
| Deep research mode with live progress | f6e529e |
| Color themes, transparency, and blur settings | d393813, 10322d9 |
| Provider config import (opencode, DeepSeek Harness, 9router) | 4f566b3 |
| Anthropic and Bedrock native providers | 130b65f |
| System prompt setting | 7a5da8b |
| Cursor-style mode picker | 2e2825a |
| TL;DR mode (terse answers) | this branch |
