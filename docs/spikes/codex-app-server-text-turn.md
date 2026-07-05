# Codex App-Server Text Turn Spike

Date: 2026-07-05

Issue: [#1 Timebox Codex app-server text turn spike](https://github.com/justinf0rfun/onpaper/issues/1)

## Goal

Validate the smallest Codex app-server path that onpaper needs for the MVP:

1. Generate or inspect the installed app-server schema.
2. Call `thread/list` and find existing Codex threads.
3. Select one existing thread.
4. Call `turn/start` with text-only input.
5. Keep `requestAccepted`, `turnStarted`, `completed`, and `failed` separate.

This spike does not build product UI and does not implement the full destination adapter.

## Reproducible Artifact

Script:

```bash
scripts/codex_app_server_text_turn_spike.py
```

The script uses only Python standard library modules. It starts Codex app-server over stdio:

```text
codex app-server --stdio
```

Safety defaults:

- `list` and `turns` redact thread names, previews, cwd values, paths, and message text.
- `send` refuses to call `turn/start` unless `--live` is passed.
- `send` requires either `--thread-id` or `--select-from-cwd`.
- Generated schema output defaults to `.onpaper-spike/codex-schema`, which is ignored by git.

## Commands

Check installed Codex:

```bash
scripts/codex_app_server_text_turn_spike.py doctor
```

Generate the installed app-server schema:

```bash
scripts/codex_app_server_text_turn_spike.py schema --out .onpaper-spike/codex-schema
```

List existing threads for this repo without printing thread content:

```bash
scripts/codex_app_server_text_turn_spike.py list \
  --cwd /Users/justin/workspace/onpaper \
  --limit 5
```

Inspect recent turn statuses without loading turn items:

```bash
scripts/codex_app_server_text_turn_spike.py turns \
  --select-from-cwd \
  --cwd /Users/justin/workspace/onpaper \
  --select-index 0 \
  --limit 5
```

Manual live send:

```bash
scripts/codex_app_server_text_turn_spike.py send \
  --live \
  --select-from-cwd \
  --cwd /Users/justin/workspace/onpaper \
  --select-index 0 \
  --confirm-select-index 0 \
  --read-only \
  --timeout 120 \
  --observe-seconds 180 \
  --message 'Spike verification only for onpaper GitHub issue #1. Please reply with exactly: onpaper app-server text turn ack'
```

For a human-selected thread, run `list`, choose a thread in Codex UI, then pass the raw id locally:

```bash
scripts/codex_app_server_text_turn_spike.py send \
  --live \
  --thread-id '<existing-thread-id>' \
  --read-only \
  --message '<text-only spike message>'
```

Do not commit raw thread ids, thread titles, previews, auth material, or message logs.

For issue #6 packet-shaped delivery, prefer `packet-delivery` over this legacy
`send` command. `packet-delivery --live` requires a raw `--thread-id` and a
matching `--confirm-thread-id` so an agent cannot silently auto-select a target.

## Installed Schema Findings

Observed Codex CLI:

```text
codex-cli 0.142.3
```

`codex app-server generate-json-schema --experimental` succeeded and produced the expected schema files for the MVP methods:

- `v2/ThreadListParams.json`
- `v2/ThreadListResponse.json`
- `v2/TurnStartParams.json`
- `v2/TurnStartResponse.json`
- `v2/TurnStartedNotification.json`
- `v2/TurnCompletedNotification.json`
- `JSONRPCRequest.json`
- `JSONRPCResponse.json`

Relevant request methods:

- `initialize`
- `thread/list`
- `thread/turns/list`
- `turn/start`

Transport finding:

- `codex app-server --stdio` accepts newline-delimited JSON-RPC messages.
- `initialize` should include `capabilities.experimentalApi: true`.
- `codex app-server daemon version` failed before daemon startup because the control socket did not exist. This is not a blocker for the stdio spike.

## Request And Response Shapes

Initialize request:

```json
{
  "id": 1,
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "onpaper-codex-text-turn-spike",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

Initialize response shape:

```json
{
  "id": 1,
  "result": {
    "userAgent": "Codex Desktop/0.142.3 (...)",
    "codexHome": "...",
    "platformFamily": "unix",
    "platformOs": "macos"
  }
}
```

Thread list request:

```json
{
  "id": 2,
  "method": "thread/list",
  "params": {
    "archived": false,
    "cwd": "/absolute/repo/path",
    "limit": 5,
    "sortKey": "recency_at",
    "sortDirection": "desc"
  }
}
```

Thread list response shape:

```json
{
  "id": 2,
  "result": {
    "data": [
      {
        "id": "...",
        "name": "...",
        "preview": "...",
        "cwd": "...",
        "status": { "type": "notLoaded" },
        "createdAt": 1783244331,
        "updatedAt": 1783244776,
        "recencyAt": 1783244336
      }
    ],
    "nextCursor": null,
    "backwardsCursor": "..."
  }
}
```

Text-only turn start request:

```json
{
  "id": 3,
  "method": "turn/start",
  "params": {
    "threadId": "<existing-thread-id>",
    "clientUserMessageId": "onpaper-spike:<attempt-id>",
    "input": [
      {
        "type": "text",
        "text": "<packet text>"
      }
    ],
    "cwd": "/absolute/repo/path",
    "sandboxPolicy": {
      "type": "readOnly",
      "networkAccess": false
    },
    "approvalPolicy": "never"
  }
}
```

Turn start response schema shape:

```json
{
  "id": 3,
  "result": {
    "turn": {
      "id": "...",
      "status": "inProgress",
      "startedAt": 1783244336,
      "completedAt": null,
      "items": []
    }
  }
}
```

Lifecycle notification shapes:

```json
{
  "method": "turn/started",
  "params": {
    "threadId": "...",
    "turn": {
      "id": "...",
      "status": "inProgress"
    }
  }
}
```

```json
{
  "method": "turn/completed",
  "params": {
    "threadId": "...",
    "turn": {
      "id": "...",
      "status": "completed"
    }
  }
}
```

## Observed Evidence

Schema generation:

```json
{
  "expectedFilesPresent": true,
  "missingExpectedFiles": [],
  "schemaDir": "/Users/justin/workspace/onpaper/.onpaper-spike/codex-schema"
}
```

`thread/list` against `/Users/justin/workspace/onpaper`:

```json
{
  "status": "completed",
  "method": "thread/list",
  "threadCount": 2,
  "nextCursorPresent": false,
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

Live `turn/start` result:

- A repo-scoped existing thread was selected with `--select-from-cwd --select-index 0`.
- `thread/turns/list` later returned one turn for that selected thread with `itemsView: "notLoaded"`.
- The turn has a stable redacted fingerprint `de86e4bc615d`.
- The observed turn status is `interrupted`, with `startedAt` populated and `completedAt: null`.
- The raw live `turn/start` response body was not retained because the observation process was interrupted before printing its final redacted report. The request shape above is the actual request shape used by the script; the response shape above is schema-derived.

Redacted status evidence:

```json
{
  "status": "completed",
  "method": "thread/turns/list",
  "turnCount": 1,
  "turns": [
    {
      "idFingerprint": "de86e4bc615d",
      "status": "interrupted",
      "startedAt": 1783244336,
      "completedAt": null,
      "itemsView": "notLoaded",
      "itemCount": 0,
      "hasError": false
    }
  ]
}
```

Interpretation:

- `thread/list` works against installed Codex app-server.
- Existing-thread selection works through a cwd-filtered list.
- A text-only `turn/start` can create a turn on the selected existing thread.
- `requestAccepted` is inferred from later turn existence, not from a retained live response body.
- Completion was not observed in this timebox.
- The observed turn became `interrupted` when the stdio client process was manually interrupted during notification observation.

## Status Semantics For onpaper

Do not collapse these states into `delivered`:

- `queued`: onpaper has created a local `DeliveryAttempt`; no app-server request has succeeded yet.
- `requestAccepted`: `turn/start` returned a successful JSON-RPC response.
- `turnStarted`: the `turn/start` response includes a turn with `status: "inProgress"` or a `turn/started` notification is observed.
- `completed`: a `turn/completed` notification or later turn inspection reports `status: "completed"`.
- `failed`: JSON-RPC error, transport error, app-server `error` notification, or turn inspection reports `status: "failed"`.

For the MVP adapter, treat `turnStarted` as the minimum evidence that Codex received the packet. Prefer `completed` for stronger delivery evidence when the app-server emits it within the observation window.

## Errors And Blockers

Observed issues:

- Managed daemon was not running: `codex app-server daemon version` could not connect to `/Users/justin/.codex/app-server-control/app-server-control.sock`.
- Codex can emit non-protocol diagnostics on stderr while still serving JSON-RPC on stdout; the spike script records only a stderr line count.
- Completion was not observed. The stdio client must remain alive while the turn runs; killing the client can interrupt the turn.

Adapter design implication:

- The production `CodexAppServerDestination` should not model `turn/start` success as final delivery.
- It should persist intermediate states and keep listening for `turn/started`, `turn/completed`, and `error`.
- It should use daemon/proxy or a long-lived stdio connection instead of one short process per send if process teardown interrupts active turns.

## Conclusion

The core MVP risk is partially retired:

- Schema support exists.
- `thread/list` works.
- Existing-thread selection is feasible.
- Text-only `turn/start` is feasible enough to create a turn.

The remaining adapter risk is lifecycle management after start. The next implementation step should build a fake app-server test seam around the exact states above, then validate whether daemon/proxy transport can observe `turn/completed` without interrupting the turn.
