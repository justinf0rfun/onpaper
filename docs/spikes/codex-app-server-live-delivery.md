# Codex App-Server Live Delivery Spike

Date: 2026-07-05

Issue: [#6 Deliver text packet to live Codex app-server](https://github.com/justinf0rfun/onpaper/issues/6)

## Goal

Validate the real Codex app-server path behind the `CodexAppServerClient` seam:

1. List real existing Codex threads.
2. Require a human-selected existing thread for live send.
3. Build a text-only `ContextPacket`-shaped delivery request.
4. Create a `DeliveryAttempt` before remote delivery starts.
5. Keep `queued`, `requestAccepted`, `turnStarted`, `completed`, and `failed` distinct.

This spike does not add OpenNook UI, Core Data, a full macOS app flow, or image delivery.

## Reproducible Artifact

Script:

```bash
scripts/codex_app_server_text_turn_spike.py
```

The issue #6 path is:

```bash
scripts/codex_app_server_text_turn_spike.py packet-delivery
```

Safety behavior:

- default mode is dry-run and does not call `turn/start`
- live mode requires `--live`
- live mode requires a raw `--thread-id`
- live mode requires `--confirm-thread-id` to exactly match `--thread-id`
- output redacts thread ids, message text, cwd, and raw response content fields; identifiers are represented by fingerprints only, not raw prefixes
- thread list and turn inspection do not print thread titles, previews, message text, or item contents
- optional `list --selection-out` writes raw thread ids only to an ignored local `.onpaper-spike/` file for human selection
- `packet-delivery --live` can read a selected raw id from that ignored file, but only when the user supplies both `--thread-selection-index` and matching `--confirm-thread-fingerprint`
- live notification handling ignores `turn/started`, `turn/completed`, and `error` notifications for other threads or known-different turns

## Safe Checks Run

Doctor:

```bash
scripts/codex_app_server_text_turn_spike.py doctor
```

Observed result:

```json
{
  "appServerCommand": "codex app-server --stdio",
  "codexPath": "/opt/homebrew/bin/codex",
  "codexVersion": "codex-cli 0.142.3",
  "status": "completed"
}
```

Schema:

```bash
scripts/codex_app_server_text_turn_spike.py schema --out .onpaper-spike/codex-schema
```

Observed result:

```json
{
  "expectedFilesPresent": true,
  "missingExpectedFiles": [],
  "schemaDir": "/Users/justin/workspace/onpaper/.onpaper-spike/codex-schema"
}
```

Real thread list, redacted:

```bash
scripts/codex_app_server_text_turn_spike.py list \
  --cwd /Users/justin/workspace/onpaper \
  --limit 5 \
  --selection-out .onpaper-spike/thread-selection.json
```

Observed result:

```json
{
  "status": "completed",
  "method": "thread/list",
  "threadCount": 2,
  "nextCursorPresent": false,
  "notifications": ["remoteControl/status/changed"],
  "selectionFile": {
    "containsRawThreadIds": true,
    "path": "/Users/justin/workspace/onpaper/.onpaper-spike/thread-selection.json",
    "threadCount": 2
  },
  "threadFieldKeys": [
    "agentNickname",
    "agentRole",
    "cliVersion",
    "createdAt",
    "cwd",
    "ephemeral",
    "forkedFromId",
    "gitInfo",
    "id",
    "modelProvider",
    "name",
    "parentThreadId",
    "path",
    "preview",
    "recencyAt",
    "sessionId",
    "source",
    "status",
    "threadSource",
    "turns",
    "updatedAt"
  ]
}
```

The selection file is intentionally local and ignored by git. It contains only index, raw id, id fingerprint, and timestamps. It does not include thread title, preview, cwd, path, or message content.

Turn status inspection, redacted and without items:

```bash
scripts/codex_app_server_text_turn_spike.py turns \
  --select-from-cwd \
  --cwd /Users/justin/workspace/onpaper \
  --select-index 0 \
  --limit 5
```

Observed result:

```json
{
  "status": "completed",
  "method": "thread/turns/list",
  "turnCount": 5,
  "turns": [
    {
      "status": "interrupted",
      "itemCount": 0,
      "itemsView": "notLoaded"
    },
    {
      "status": "completed",
      "itemCount": 0,
      "itemsView": "notLoaded"
    }
  ]
}
```

Daemon/proxy check:

```bash
scripts/codex_app_server_text_turn_spike.py daemon-proxy
```

Observed result:

```json
{
  "status": "failed",
  "method": "daemon-proxy",
  "liveTurnSent": false,
  "checks": [
    {
      "command": "codex app-server daemon start",
      "status": "failed",
      "returnCode": 1
    },
    {
      "command": "codex app-server daemon version",
      "status": "failed",
      "returnCode": 1
    },
    {
      "command": "codex app-server proxy",
      "status": "failed",
      "errorCategory": "jsonRpcOrTransport"
    }
  ]
}
```

The daemon/proxy path remains blocked on this machine because the managed app-server daemon is not available from the current Homebrew CLI installation. The stdio path is usable for safe list and inspect operations.

## Packet Delivery Dry-Run

Dry-run command:

```bash
scripts/codex_app_server_text_turn_spike.py packet-delivery \
  --packet-id issue-6-dry-run \
  --message 'onpaper issue #6 dry-run text packet' \
  --cwd /Users/justin/workspace/onpaper \
  --read-only
```

Observed result:

```json
{
  "status": "queued",
  "method": "packet-delivery",
  "liveTurnSent": false,
  "manualThreadSelectionRequired": true,
  "packet": {
    "idFingerprint": "...",
    "textByteCount": 36
  },
  "attempt": {
    "id": "attempt-...",
    "packetIdFingerprint": "...",
    "destination": "codexAppServer",
    "targetIdFingerprint": "...",
    "clientUserMessageIdFingerprint": "...",
    "status": "queued",
    "completedAt": null,
    "remoteTurnIdFingerprint": null,
    "errorCode": null,
    "errorMessage": null,
    "rawErrorJSON": null
  },
  "request": {
    "method": "turn/start",
    "params": {
      "threadId": {
        "fingerprint": "..."
      },
      "clientUserMessageId": {
        "fingerprint": "..."
      },
      "input": [
        {
          "type": "text",
          "text": "[redacted]"
        }
      ],
      "cwd": "[redacted]",
      "sandboxPolicy": {
        "type": "readOnly",
        "networkAccess": false
      },
      "approvalPolicy": "never"
    }
  },
  "timeline": [
    {
      "state": "queued"
    }
  ],
  "safety": {
    "dryRunRequiresNoLiveFlag": true,
    "liveRequiresThreadIdConfirmation": true,
    "textRedactedFromOutput": true
  }
}
```

This proves the local `DeliveryAttempt` is created before remote delivery. It does not prove `turn/start` acceptance because live mode was not executed.

## Live Send Procedure

Live send was not executed during this run because no raw existing thread id was explicitly selected by the user. The agent must not silently choose the current thread or default to index `0`.

Manual live send procedure:

1. Run safe list:

   ```bash
   scripts/codex_app_server_text_turn_spike.py list \
     --cwd /Users/justin/workspace/onpaper \
     --limit 5 \
     --selection-out .onpaper-spike/thread-selection.json
   ```

2. Choose the existing destination thread in Codex UI or inspect `.onpaper-spike/thread-selection.json` locally. Do not paste the raw id into docs or issue comments.

3. Preferred: run live packet delivery through the ignored selection file. This avoids putting the raw thread id in shell history while still requiring an explicit index and fingerprint confirmation:

   ```bash
   scripts/codex_app_server_text_turn_spike.py packet-delivery \
     --live \
     --thread-selection-file .onpaper-spike/thread-selection.json \
     --thread-selection-index <selected-index> \
     --confirm-thread-fingerprint '<selected-idFingerprint>' \
     --packet-id issue-6-live-check \
     --message 'onpaper issue #6 live text packet delivery check. Please acknowledge receipt only.' \
     --cwd /Users/justin/workspace/onpaper \
     --read-only \
     --timeout 120 \
     --observe-seconds 180
   ```

4. Alternative: run live packet delivery with the raw thread id locally:

   ```bash
   scripts/codex_app_server_text_turn_spike.py packet-delivery \
     --live \
     --thread-id '<existing-thread-id>' \
     --confirm-thread-id '<existing-thread-id>' \
     --packet-id issue-6-live-check \
     --message 'onpaper issue #6 live text packet delivery check. Please acknowledge receipt only.' \
     --cwd /Users/justin/workspace/onpaper \
     --read-only \
     --timeout 120 \
     --observe-seconds 180
   ```

5. Inspect resulting turn statuses without content:

   ```bash
   scripts/codex_app_server_text_turn_spike.py turns \
     --thread-id '<existing-thread-id>' \
     --limit 5
   ```

Do not commit the raw thread id, thread title, preview, message contents, token, socket path, or raw log output.

## Live State Mapping

`packet-delivery --live` maps app-server evidence into `DeliveryAttempt` states as follows:

- local attempt creation before `turn/start` -> `queued`
- JSON-RPC success without a turn object -> `requestAccepted`
- `turn/start` response with `turn.status` of `inProgress` or `interrupted` -> `turnStarted`
- `turn/started` notification -> `turnStarted`
- `turn/completed` notification with `completed` -> `completed`
- JSON-RPC error, transport error, app-server `error`, or failed completion -> `failed`

`requestAccepted` and `turnStarted` are not collapsed into `completed`.

Live notification filtering:

- notifications for a different `params.threadId` are ignored
- once a turn id is known, notifications for a different `params.turn.id` are ignored
- this prevents unrelated app-server events from completing or failing the current `DeliveryAttempt`

## Current Conclusion

Issue #6 is partially de-risked:

- real `thread/list` works through app-server stdio
- real redacted turn status inspection works without loading item contents
- the packet-shaped live delivery command exists and has a safe dry-run path
- the command creates a queued `DeliveryAttempt` before any live remote call
- live sending now requires explicit user-selected raw thread id confirmation
- raw thread ids can be written to an ignored local selection file for human choice without printing titles/previews/content
- live delivery can read that ignored selection file when the user confirms the selected index and id fingerprint
- live event mapping now filters unrelated thread and known-different-turn notifications

Issue #6 is not fully closed by this run because no live `turn/start` was executed against a human-selected existing thread. The next step is to run the live command above with an explicitly selected thread id, then record whether the final state is `requestAccepted`, `turnStarted`, `completed`, or `failed`.
