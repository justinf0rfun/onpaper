# Codex App-Server Lifecycle Spike

Date: 2026-07-05

Issue: [#13 Pin Codex app-server delivery state seam and lifecycle spike](https://github.com/justinf0rfun/onpaper/issues/13)

## Goal

Follow up the text-turn spike from issue #1 by pinning the future `CodexAppServerDestination` state seam and checking whether app-server daemon/proxy transport can solve the completion-observation gap.

This is not product UI and not the full MVP app. It is a narrow adapter lifecycle slice.

## Swift Test Seam

Added a minimal SwiftPM package with one library target:

```text
Sources/OnPaperDestinations/
Tests/OnPaperDestinationsTests/
```

The seam is intentionally smaller than the app-server protocol:

```swift
public protocol CodexAppServerClient {
    func listThreads(_ request: CodexThreadListRequest) async throws -> CodexThreadPage
    func startTurn(_ request: CodexTurnStartRequest) async throws -> CodexTurnStartResponse
    func events() -> AsyncStream<CodexServerEvent>
}
```

Delivery status is represented as:

```swift
public enum DeliveryAttemptStatus {
    case queued
    case requestAccepted
    case turnStarted
    case completed
    case failed
}
```

The test seam records a `DeliveryAttempt` with:

- destination
- target thread id
- `clientUserMessageId`
- status
- timestamps
- remote turn id when known
- raw error details when failed

No OpenNook UI, Core Data store, packet composer, or product shell was added.

## State Semantics

The adapter must not collapse intermediate states into `completed`.

```text
queued
  -> requestAccepted
  -> turnStarted
  -> completed
```

Failures can happen at any point:

```text
queued -> failed
requestAccepted -> failed
turnStarted -> failed
```

Meanings:

- `queued`: local `DeliveryAttempt` exists before remote delivery starts.
- `requestAccepted`: `turn/start` returned JSON-RPC success, but no turn start evidence exists yet.
- `turnStarted`: `turn/start` returned an in-progress/interrupted turn or a `turn/started` notification was observed.
- `completed`: `turn/completed` reported a completed turn.
- `failed`: JSON-RPC error, app-server error event, failed completion event, or transport failure.

For product reporting, `turnStarted` can support "sent to Codex" style copy, but `completed` must remain a stronger audit state.

## Fake Coverage

`swift test` covers:

- fake thread list success through `CodexAppServerDestination.listThreads`
- `turn/start` JSON-RPC success with no turn object -> `requestAccepted`
- `turn/start` response with `inProgress` turn -> `turnStarted`
- `turn/started` notification -> `turnStarted`
- `turn/completed` with `completed` status -> `completed`
- `turn/completed` with `failed` status -> `failed`
- JSON-RPC-style thrown error -> `failed` with raw error details
- request accepted with no completion event -> remains pending, not completed

This fixes the issue #1 ambiguity where a text turn could be created but completion was not observed.

## Request And Event Shapes

Thread list request shape:

```swift
CodexThreadListRequest(
    archived: false,
    limit: 30,
    sortKey: "recency_at",
    sortDirection: "desc"
)
```

Text turn request shape:

```swift
CodexTurnStartRequest(
    threadId: "<existing-thread-id>",
    input: [.text("<rendered packet text>")],
    clientUserMessageId: "onpaper:<packet-id>:<attempt-id>"
)
```

Start response shape:

```swift
CodexTurnStartResponse(
    turn: CodexTurn(id: "<turn-id>", status: .inProgress)
)
```

Lifecycle events:

```swift
CodexServerEvent.turnStarted(
    threadId: "<existing-thread-id>",
    turn: CodexTurn(id: "<turn-id>", status: .inProgress)
)
```

```swift
CodexServerEvent.turnCompleted(
    threadId: "<existing-thread-id>",
    turn: CodexTurn(id: "<turn-id>", status: .completed)
)
```

```swift
CodexServerEvent.error(
    threadId: "<existing-thread-id>",
    code: "<json-rpc-code>",
    message: "<message>",
    rawJSON: "<raw error json>"
)
```

The real app-server adapter should map JSON-RPC responses and notifications into these small types rather than exposing the whole app-server schema to onpaper.

## Daemon/Proxy Check

The existing spike script now includes a safe daemon/proxy check:

```bash
scripts/codex_app_server_text_turn_spike.py daemon-proxy
```

It performs:

1. `codex app-server daemon start`
2. `codex app-server daemon version`
3. `codex app-server proxy` with a JSON-RPC `initialize` request

It does not send `turn/start`.

Observed result on this machine:

```json
{
  "status": "failed",
  "method": "daemon-proxy",
  "liveTurnSent": false,
  "checks": [
    {
      "command": "codex app-server daemon start",
      "status": "failed",
      "returnCode": 1,
      "stderrLineCount": 8
    },
    {
      "command": "codex app-server daemon version",
      "status": "failed",
      "returnCode": 1,
      "stderrLineCount": 4
    },
    {
      "command": "codex app-server proxy",
      "status": "failed",
      "errorMessage": "app-server process exited before response",
      "appServerStderrLineCount": 2
    }
  ]
}
```

The inspected stderr category is:

- daemon start failed because the managed standalone Codex install was not found at the fixed installer path.
- daemon version failed because the app-server control socket did not exist.
- proxy failed because the control socket did not exist.

No auth tokens, raw thread titles, previews, or message contents were read or committed.

## Conclusion

The fake adapter seam is ready for the next real adapter implementation step:

- `requestAccepted`, `turnStarted`, `completed`, and `failed` are distinct and tested.
- accepted-without-completion remains pending instead of becoming delivered.
- raw error details have a place on `DeliveryAttempt`.

Daemon/proxy is not currently usable on this machine because the Codex installation is Homebrew CLI based, while `codex app-server daemon start` expects the standalone installer-managed path. The next live lifecycle validation should either:

1. install the standalone Codex app-server layout required by `daemon start`, then rerun `daemon-proxy`, or
2. keep a long-lived stdio app-server process for the real adapter and prove it can observe `turn/completed` without interrupting the turn.

Do not proceed to product UI until one of those lifecycle paths can observe completion or the MVP explicitly accepts `turnStarted` as the minimum delivery evidence.
