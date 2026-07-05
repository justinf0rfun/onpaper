# onpaper Context

onpaper / 跃然纸上 is a macOS notch-based AI context tray for developers.

## Product Terms

- **onpaper**: The product. A native Swift macOS app that turns local development context into AI-ready task packets.
- **OpenNook**: The notch shell and interaction layer. OpenNook owns the notch surface, hotkey, compact/expanded lifecycle, settings chrome, and file picker mechanics.
- **ContextAsset**: One explicitly captured raw context item. P0 asset kinds are `text`, `code`, `log`, `image`, `file`, and `url`.
- **ContextPacket**: One AI task package containing a user-written goal, selected intent, ordered assets, and destination target.
- **DeliveryAttempt**: One auditable attempt to deliver a packet to a destination. Packet status is derived from attempts.
- **AIDestination**: A destination adapter such as a Codex thread, Claude session, or copy-prompt fallback.
- **Codex app-server**: The preferred MVP integration path for listing Codex threads and starting turns.
- **Copy-prompt fallback**: Degraded delivery path when app-server delivery is unavailable or fails. It is not the MVP success path.

## Product Boundaries

- onpaper is an AI context router, not a generic clipboard manager.
- P0 capture is explicit only. Do not persist full clipboard history by default.
- UI previews are derived display data. They must not be used as canonical delivery content.
- File assets are reference-only in P0 unless a later issue explicitly adds snapshots or security-scoped bookmarks.
- Claude is P1 validation, not Codex-equivalent MVP scope.

## Architecture Vocabulary

- **Shell**: OpenNook-hosted SwiftUI presentation and app chrome.
- **Capture**: Reads current pasteboard or file drop only when the user explicitly asks.
- **AssetStore**: Persists asset metadata and sidecar files locally.
- **PacketComposer**: Produces deterministic packet previews and destination renderings from full asset data.
- **Destination adapter**: Encapsulates a specific delivery target's protocol or command behavior.

## Required Reading

- `docs/onpaper-prd.md`
- `docs/onpaper-technical-design.md`

