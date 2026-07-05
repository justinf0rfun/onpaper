# onpaper / 跃然纸上

Context packets for Codex and Claude.

onpaper is a macOS notch-based AI context tray for developers. It is designed to turn scattered local development context into an agent-ready task packet and route that packet into the right AI coding thread.

The MVP is Codex-first: explicitly capture local context, compose a typed packet, select an existing Codex thread, send through Codex app-server, and record the delivery attempt. Claude remains in the v1 architecture as a later destination validation track, but it is not the MVP proof workflow.

## What It Is

onpaper is:

- A native Swift macOS app.
- Built around OpenNook as the notch shell and interaction surface.
- A local-first context tray for AI coding workflows.
- A packet composer and delivery layer for Codex-first handoff.

onpaper is not:

- A generic clipboard manager.
- A full clipboard history app.
- A prompt library.
- A note-taking app.
- A replacement for Codex, Claude, or an editor.

## MVP Workflow

The initial workflow is:

1. Copy a log, code snippet, screenshot, URL, or file path.
2. Explicitly capture the current clipboard into onpaper.
3. Open onpaper from the notch.
4. Select one or more recent captured assets.
5. Choose an intent and write a short goal.
6. Select an existing Codex thread.
7. Preview the packet.
8. Send the packet through Codex app-server.
9. Record the delivery result and allow retry or copy-prompt fallback if needed.

## Core Model

The product centers on four concepts:

- `ContextAsset`: one captured raw context item, such as text, code, log, image, file reference, or URL.
- `ContextPacket`: one task package containing goal, intent, ordered assets, and target destination.
- `DeliveryAttempt`: one auditable attempt to deliver a packet.
- `AIDestination`: a delivery target such as a Codex thread, Claude session, or copy-prompt fallback.

UI previews are derived display data. They must never become the canonical content sent to an AI tool.

## Architecture Direction

The planned app architecture separates:

- OpenNook shell and SwiftUI presentation.
- Explicit clipboard capture.
- Local asset persistence.
- Packet composition.
- Codex/Claude destination adapters.
- Delivery status and retry audit.

The implementation should keep domain modules independent from OpenNook so capture, persistence, packet rendering, and delivery can be tested without launching the notch UI.

## Current Status

This repository currently contains product and technical planning docs. Implementation has not started.

Key docs:

- [Product Requirements](docs/onpaper-prd.md)
- [Technical Design](docs/onpaper-technical-design.md)

The first implementation issues have been published in GitHub issues and are ordered around the Codex-first tracer bullet.

## Development Notes

Expected baseline:

- Swift / SwiftUI native macOS app.
- macOS 15+ minimum, inherited from OpenNook.
- OpenNook local package dependency during early development.
- Core Data backed by SQLite for metadata.
- Application Support sidecar files for original images, thumbnails, and future snapshots.
- Fake Codex app-server client tests before live app-server delivery.

## Privacy Boundary

onpaper should not persist a full clipboard history by default.

P0 capture is explicit only:

- Observe current clipboard only when needed.
- Persist only user-captured assets.
- Store data locally.
- Preview before send.
- Delete captured assets and sidecar files.
- Do not claim automatic secret or PII detection in MVP.

## Prior Art

Handy is reference material, not the implementation base. It proves macOS clipboard capture, local persistence, source app metadata, image thumbnails, search/filter, and multi-select composition are feasible.

onpaper should not copy Handy's prompt-copy-first model, preview-as-content behavior, or generic clipboard history positioning.
