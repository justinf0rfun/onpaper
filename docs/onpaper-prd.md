# onpaper PRD

Status: Formal draft  
Date: 2026-07-05  
Product name: onpaper / 跃然纸上  
Subtitle: Context packets for Codex and Claude

## 1. Summary

onpaper is a macOS notch-based AI context tray for developers. It turns scattered local development context into an agent-ready task packet and routes that packet into the right AI work session.

The MVP is Codex-first. It must prove one end-to-end workflow: explicitly capture multiple local context assets, compose a task packet, select an existing Codex thread, send the packet through Codex app-server, and record the delivery result.

Claude remains in the v1 product architecture as an `AIDestination`, but it is not the MVP proof workflow. Claude support starts as a validation track around Claude Code CLI/session capabilities and fake command-runner tests.

onpaper is not a generic clipboard manager, prompt library, note-taking app, or AI chat replacement. The core product bet is that developers need a fast, local, typed handoff layer between messy context sources and AI coding agents.

## 2. Problem

Developers often have the right context for an AI coding task spread across clipboard text, terminal logs, screenshots, code snippets, file paths, browser pages, issue text, and local project state. Moving that context into an AI tool is still manual and lossy.

A typical workflow is:

1. Copy an error, stack trace, code snippet, screenshot, or issue excerpt.
2. Switch into Codex or Claude.
3. Find the right thread, project, or session.
4. Paste text, attach images separately, and rewrite the task.
5. Explain where the context came from.
6. Hope the agent has enough information to act correctly.

This process is slow, repetitive, and error-prone. General clipboard managers solve recall, not AI handoff. They save too much, create noise, and treat every copied item as equally important. Prompt composers help assemble text, but they usually collapse typed context into plain text and do not reliably deliver it into the right AI work thread.

onpaper exists to make AI handoff fast, explicit, typed, local, and reliable.

## 3. Target User

The initial target user is a developer using Codex and Claude in daily local development work, starting with the founder's own workflow.

The first user is expected to:

- Work across terminal, editor, browser, issue tracker, screenshots, and AI coding agents.
- Frequently send logs, code, screenshots, diffs, URLs, and file references into Codex.
- Care more about speed and reliability than broad clipboard history.
- Prefer local-first tools that do not silently persist sensitive clipboard data.
- Want the notch interaction to be a primary surface, not a novelty launcher.

## 4. Positioning

onpaper is an AI context router and context tray.

It should be described as:

- A notch-based context tray for AI coding work.
- A way to turn scattered local context into a structured task packet.
- A delivery layer for Codex-first agent handoff.

It should not be described as:

- A clipboard manager.
- A prompt manager.
- A note-taking app.
- A general AI assistant.
- A full replacement for Codex, Claude, or an editor.

The English name "onpaper" may imply documents or theory, so product copy should pair it with concrete developer-language positioning such as "Context packets for Codex and Claude."

## 5. Product Principles

### Explicit over ambient

The app must not persist full clipboard history by default. The user explicitly captures material into onpaper before it becomes a persistent `ContextAsset`.

### Typed over flattened

The app should preserve asset semantics. Text stays text, code/logs keep full content, images stay image inputs where supported, and file paths remain file references. UI previews are never the source of truth for delivery.

### Delivery over prompt assembly

The MVP succeeds only when a packet is delivered into a real Codex thread through the preferred integration path. Copy-prompt is a fallback, not the core product promise.

### Notch-first, domain-independent

The product must ship as an OpenNook-based notch experience. The notch is the primary interaction surface. However, the domain model and delivery logic must remain independent from the OpenNook shell.

### Codex-first, Claude-compatible

Codex is the first deep integration target because its app-server path supports the MVP thread delivery workflow. Claude remains in scope as a destination type, but the MVP must not assume feature parity with Codex.

## 6. MVP Workflow

The MVP killer workflow is:

1. User copies a relevant log, code snippet, screenshot, URL, or file path.
2. User explicitly captures the current clipboard into onpaper.
3. User opens onpaper from the notch.
4. User selects at least two recent captured assets.
5. User chooses an intent and writes a short goal.
6. User selects an existing Codex thread.
7. User previews the packet.
8. User sends the packet.
9. onpaper sends a new turn to the selected Codex thread through Codex app-server.
10. onpaper records a `DeliveryAttempt` with delivered or failed status.
11. If delivery fails, the packet remains intact and can be retried or copied as a fallback prompt.

This workflow must feel faster and less lossy than switching into a full app and manually pasting each piece of context.

## 7. Scope

### P0: MVP

- OpenNook-based notch tray as the primary interaction surface.
- Explicit capture of the current clipboard into onpaper.
- Explicit capture-and-open shortcut.
- Recent captured assets list.
- Current packet selection.
- Asset kinds: `text`, `code`, `log`, `image`, `file`, `url`.
- Full underlying asset content or durable local asset path.
- Source metadata where available: source app, source URL/path, capture time, original type.
- Multi-asset packet composition.
- User-written goal.
- User-selected intent: `debug`, `implement`, `review`, `explain`.
- Packet preview before send.
- Codex thread list.
- Select existing Codex thread.
- Send packet as a new Codex turn through app-server.
- Persist `ContextPacket` and `DeliveryAttempt`.
- Show delivery status.
- Retry failed delivery.
- Copy-prompt fallback after failure or unavailable integration.
- Delete captured asset.
- Local-only storage.
- No full clipboard history persistence.

### P0.5: Near-MVP if cheap after integration validation

- Start a new Codex thread with a packet if app-server validation makes this straightforward.
- Basic thread display metadata, such as title, repo/path, and last updated time, if available from the app-server.

### P1: First expansion

- Temporary clipboard Candidate surface for likely AI context.
- Conservative classification and prioritization of likely AI context.
- Search recent captured assets.
- Type filters.
- Resume last Codex thread.
- Current repo thread suggestions.
- Thread search/filter.
- Claude Code CLI delivery spike.
- Claude fake command-runner integration tests.
- Archive old packets.
- Optional secret/PII warning exploration.

### P2: Later

- Long-term context history UX.
- More asset subtypes, such as `issue`, `diff`, `thought`, `markdown_spec`, and `stack_trace`.
- Richer automatic task drafting.
- Team sharing.
- Sync.
- Additional AI destinations.
- Advanced packet templates.
- Background retry queue.

## 8. Capture Policy

onpaper uses a three-level capture model:

### Level 0: Observe

The app may inspect the current clipboard candidate without saving it. This is a design principle, not a required MVP feature beyond explicit capture.

### Level 1: Candidate

Likely AI-relevant clipboard material may appear temporarily in the notch surface. Candidate behavior is P1, not P0.

### Level 2: Asset

Only explicit user action persists material as a `ContextAsset`. P0 starts here.

MVP requirements:

- Do not persist full clipboard history.
- Do not automatically save every clipboard change.
- Persist only explicit captures.
- Preserve full captured content or durable local asset paths.
- Show a short UI preview, but never use preview text as delivery content.
- Allow asset deletion.

## 9. Domain Model

The domain model should be independent from OpenNook and from any single AI integration.

### ContextAsset

A `ContextAsset` is one captured raw context item.

P0 fields:

```text
ContextAsset
  id
  kind: text | code | log | image | file | url
  title
  preview
  content?
  localAssetPath?
  sourceApp?
  sourceURL?
  capturedAt
  metadata
```

Rules:

- `content` stores full text content for text-like assets.
- `localAssetPath` stores durable local paths for images and file-backed assets.
- `preview` is derived display data only.
- Subtypes such as `issue`, `diff`, `thought`, `markdown_spec`, and `stack_trace` belong in `metadata` until there is evidence they need first-class model status.

### ContextPacket

A `ContextPacket` is one AI task package.

P0 fields:

```text
ContextPacket
  id
  intent: debug | implement | review | explain
  goal
  assetIds
  target
  status: draft | pending | delivered | failed | archived
  createdAt
  updatedAt
```

Rules:

- The user writes `goal`.
- The user selects `intent`.
- The app formats the packet deterministically.
- No automatic goal generation or AI summarization in MVP.
- Packet ordering should preserve the user's selected asset order.

### DeliveryAttempt

A `DeliveryAttempt` records one attempt to send a packet.

P0 fields:

```text
DeliveryAttempt
  id
  packetId
  destination
  targetId
  status: pending | delivered | failed
  startedAt
  completedAt?
  errorMessage?
  integrationMetadata
```

Rules:

- Create a packet before delivery.
- Create a delivery attempt for each send.
- Failed delivery must not destroy the packet.
- Retry creates a new delivery attempt or updates attempt history without losing prior failure data.
- No background retry daemon in MVP.

### AIDestination

An `AIDestination` is a target that can receive a packet.

P0:

```text
AIDestination
  codexThread
  copyPromptFallback
```

v1 architecture:

```text
AIDestination
  codexThread
  claudeSession
  copyPromptFallback
```

Rules:

- Destination abstraction must not imply feature parity.
- Codex and Claude capability differences should be explicit in integration code and product copy.

## 10. Packet Example

This example is illustrative. It defines the expected user-facing shape, not the final wire format.

```text
Intent: debug

Goal:
Fix the failing login test in this repo. Identify the root cause before changing code.

Assets:
1. log: pytest failure output from Terminal, captured 2026-07-05 15:42
2. code: copied LoginView test snippet from Xcode, captured 2026-07-05 15:43
3. image: screenshot of the failed UI state, local path /.../assets/login-failure.png

Instructions:
Use the attached context as source material. Preserve file paths and image references.
If context is insufficient, ask before changing unrelated code.
```

The integration layer decides how this maps to Codex app-server payloads, including text blocks and local image-style inputs.

## 11. Codex Requirements

Codex is the MVP delivery destination.

### P0 requirements

- Use Codex app-server as the preferred integration path.
- List existing Codex threads.
- Let the user select a thread.
- Send a packet as a new turn in that thread.
- Preserve text, file, and image semantics where the app-server supports them.
- Record delivery status.
- Record integration errors.
- Provide retry.
- Provide copy-prompt fallback if app-server delivery is unavailable or fails.

### Fallback requirements

Codex CLI fallback may support flows such as:

- `codex resume`
- `codex resume --all`
- `codex resume --last`
- `codex exec resume`

CLI fallback is not the preferred MVP success path. It is useful for degraded operation and integration testing, but the product proof requires app-server delivery.

### Non-goals

- Do not use simulated paste as the primary Codex delivery mechanism.
- Do not directly edit Codex internal state outside supported APIs.
- Do not build a Codex chat replacement.

## 12. Claude Requirements

Claude support is in scope for v1 architecture but not the MVP proof workflow.

P1 validation should investigate:

- Claude Code CLI session capabilities.
- Continue/resume behavior.
- Session targeting.
- Command construction.
- Stdin or file payload behavior.
- JSON output/session listing where available.
- Failure and retry behavior through a fake command runner.

Requirements:

- Do not assume parity with Codex app-server.
- Do not promise thread listing or structured turn delivery until verified.
- Keep `AIDestination` capable of representing Claude sessions without forcing Codex semantics onto Claude.

## 13. Notch And OpenNook Requirements

onpaper must be an OpenNook-based notch experience.

P0 interaction requirements:

- The notch is the primary entry point.
- Compact state communicates capture readiness and recent delivery status.
- Expanded state supports recent assets, current packet selection, goal, intent, destination, preview, send, and status.
- Capture-and-open should be available from keyboard shortcut.
- The workflow should be usable without switching to a large standalone clipboard window.
- The surface should feel quiet, utilitarian, and repeatable for developer work.

Architecture constraint:

- OpenNook owns shell, presentation, notch behavior, hotkeys, hover/expand behavior, and module hosting.
- onpaper owns capture, asset persistence, packet composition, destination integration, and delivery attempts.
- `ContextAsset`, `ContextPacket`, `DeliveryAttempt`, and delivery services must be testable without OpenNook UI.

Validation requirement:

- Verify OpenNook can host the MVP tray interaction without broad upstream framework changes.
- Narrow OpenNook fixes are acceptable if required by the onpaper shell.

## 14. Privacy And Local Data

MVP privacy requirements:

- No full clipboard history persistence.
- No automatic persistence of every clipboard item.
- Explicit capture before local persistence.
- Local-only storage.
- No hosted backend.
- No cloud sync.
- Packet preview before send.
- Delete captured asset.
- Failed sends must keep packets local and retryable.

MVP does not include automatic sensitive-content detection. That may be explored later as an optional warning system, but it should not be treated as a security guarantee.

## 15. Success Criteria

The MVP is successful only if the founder can use it for real Codex work.

### Functional success

- User can capture at least two assets into onpaper.
- User can compose a packet with goal and intent.
- User can select an existing Codex thread.
- Codex receives the packet as a new turn through app-server.
- onpaper records a delivered `DeliveryAttempt`.
- Failed delivery preserves the packet and allows retry or copy fallback.

### Workflow success

- Time-to-send from copied context to delivered Codex packet is under 60 seconds.
- A typical packet includes at least two selected assets.
- At least one successful packet uses a non-plain-text asset, such as image, file, or URL.
- Codex should not require the same context to be manually pasted again for the task to begin.
- After one week of real founder use, onpaper is used for at least five real AI handoffs instead of manual paste.

### Product success

- The product feels like a notch-native AI context tray, not a generic clipboard history app.
- The user trusts that clipboard contents are not silently accumulated.
- The user trusts that delivery status reflects what happened.

## 16. Verified Facts

These facts are treated as verified for PRD purposes:

- Handy demonstrates that macOS clipboard capture, local persistence, Core Data history, search/filter, image thumbnails, source app metadata, and multi-select composition are feasible in the local environment.
- Handy should not be copied wholesale because its current model is too prompt-copy oriented and uses preview text as content in places.
- OpenNook is the intended shell and notch surface layer for onpaper.
- Codex app-server documentation/schema indicate support for thread lifecycle and turn APIs including `thread/list`, `thread/resume`, `thread/start`, and `turn/start`.
- Codex supports local image-style inputs in the documented/schema-verified integration path.
- Codex CLI fallback commands include `codex resume`, `codex resume --all`, `codex resume --last`, and `codex exec resume`.

## 17. Hypotheses

### Product hypotheses

- Developers will prefer explicit AI context capture over automatic clipboard history for sensitive development workflows.
- A notch-first context tray will be faster than switching into a standalone clipboard app or AI app.
- Multi-asset packets will reduce the need to manually re-explain context to Codex.
- The founder will use onpaper repeatedly if delivery is reliable and packet assembly is fast.

### Technical hypotheses

- OpenNook can host the MVP tray interaction without broad framework changes.
- Codex app-server can support text plus local image-style assets in the same practical packet workflow.
- App-server delivery can be made reliable enough for day-to-day use.
- Claude Code CLI can later support a useful, though not necessarily equivalent, destination workflow.

## 18. Open Questions And Spikes

### Spike 1: Codex app-server delivery

Validate end to end:

- List threads.
- Select one thread.
- Send text packet.
- Send packet with a local image asset.
- Observe success/failure events.
- Record `DeliveryAttempt`.

This spike gates MVP implementation quality.

### Spike 2: OpenNook tray hosting

Validate:

- Compact notch state.
- Expanded tray state.
- Keyboard shortcut capture-and-open.
- Multi-asset selection.
- Goal/intent entry.
- Destination picker.
- Send status.

This spike gates the notch-first product requirement.

### Spike 3: Local asset persistence

Validate:

- Text/code/log storage preserves full content.
- Image capture creates durable local asset paths.
- File paths and URLs retain reference semantics.
- Preview text is derived, never canonical.

### Spike 4: Claude CLI destination

Validate after Codex MVP path:

- Session listing or targeting if available.
- Continue/resume behavior.
- Packet payload mechanics.
- Failure modes.
- Fake command-runner test seam.

## 19. Testing Requirements

Test external behavior, not UI implementation details.

Highest-value test seams:

- Capture creates the right `ContextAsset` with full content or durable local path.
- Explicit capture persists; ordinary clipboard changes do not.
- Packet composition preserves selected asset order and type.
- Packet formatter produces deterministic output.
- Codex fake app-server supports `thread/list`, `thread/resume`, `thread/start`, and `turn/start` behaviors used by onpaper.
- Delivery attempt records success, failure, retry, target, and error data.
- Failed delivery does not lose packet data.
- Copy-prompt fallback uses full asset content, not previews.
- OpenNook UI tests cover only critical workflow behavior: open, capture, select, compose, choose destination, send, status.

Do not overbuild tests around speculative classifiers or long-term history in MVP.

## 20. Prior Art: Handy

Handy is reference material, not the implementation base.

Use Handy as evidence and inspiration for:

- macOS clipboard capture.
- Local persistence.
- Source app metadata.
- Image thumbnails.
- Search/filter interaction patterns.
- Multi-select composition.

Do not copy Handy's product model:

- Prompt-copy-first handoff.
- Preview text as delivery source of truth.
- Generic clipboard manager positioning.
- Full history as the central product surface.
- Large command-panel assumptions that conflict with notch-first interaction.

onpaper code should be written around `ContextAsset`, `ContextPacket`, `DeliveryAttempt`, and `AIDestination`.

## 21. Out Of Scope

- Generic clipboard manager positioning.
- Full clipboard history persistence by default.
- Supporting every AI tool in v1.
- Claude as an MVP-equivalent integration.
- iCloud sync or cross-device sync.
- Team sharing.
- Hosted backend services.
- Web dashboard.
- Note-taking workflows.
- AI chat UI replacement.
- Full task/project management.
- Primary delivery through UI automation or simulated paste.
- Automatic editing of Codex or Claude internal state outside supported APIs.
- Complex ML-based clipboard classification in MVP.
- Automatic goal generation in MVP.
- Automatic sensitive-content detection in MVP.
- Long-term searchable history in MVP.
- Deep visual polish beyond what is necessary to validate the workflow.
- Reusing Handy wholesale.
- Broad OpenNook framework changes unless narrowly required by onpaper.
