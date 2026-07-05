#!/usr/bin/env python3
"""Codex app-server text turn spike for onpaper.

This script intentionally avoids printing thread names, previews, cwd values, or
message text. Use it to prove the app-server protocol shape and status lifecycle
without committing private Codex thread content.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from select import select
from typing import Any


CLIENT_INFO = {"name": "onpaper-codex-text-turn-spike", "version": "0.1.0"}
STATUS_EVENTS = {
    "queued",
    "requestAccepted",
    "turnStarted",
    "completed",
    "failed",
}
REDACTED = "[redacted]"


class AppServerError(Exception):
    pass


class JsonRpcClient:
    def __init__(self, command: list[str], timeout_seconds: float) -> None:
        self.command = command
        self.timeout_seconds = timeout_seconds
        self.next_id = 1
        self.process: subprocess.Popen[str] | None = None
        self.stderr_line_count = 0

    def __enter__(self) -> "JsonRpcClient":
        self.process = subprocess.Popen(
            self.command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        return self

    def __exit__(self, *_: object) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def request(
        self,
        method: str,
        params: dict[str, Any],
        *,
        collect_until: set[str] | None = None,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        if not self.process or not self.process.stdin:
            raise AppServerError("app-server process is not running")

        request_id = self.next_id
        self.next_id += 1
        payload = {"id": request_id, "method": method, "params": params}
        self.process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

        return self._read_until_response(request_id, collect_until or set())

    def collect_notifications(self, methods: set[str], window_seconds: float) -> list[dict[str, Any]]:
        return self._read_notifications(methods, window_seconds)

    def _read_until_response(
        self,
        request_id: int,
        collect_until: set[str],
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        if not self.process or not self.process.stdout or not self.process.stderr:
            raise AppServerError("app-server process is not running")

        notifications: list[dict[str, Any]] = []
        deadline = time.monotonic() + self.timeout_seconds
        response: dict[str, Any] | None = None

        while time.monotonic() < deadline:
            ready, _, _ = select([self.process.stdout, self.process.stderr], [], [], 0.25)
            for stream in ready:
                line = stream.readline()
                if not line:
                    continue
                if stream is self.process.stderr:
                    self.stderr_line_count += 1
                    continue
                message = json.loads(line)
                if message.get("id") == request_id:
                    response = message
                    if not collect_until:
                        return response, notifications
                elif "method" in message:
                    notifications.append(message)
                    if message.get("method") in collect_until and response is not None:
                        return response, notifications

            if response is not None and not collect_until:
                return response, notifications
            if response is None and self.process.poll() is not None:
                raise AppServerError("app-server process exited before response")

        if response is not None:
            return response, notifications
        raise AppServerError(f"no response for JSON-RPC request {request_id} before timeout")

    def _read_notifications(self, methods: set[str], window_seconds: float) -> list[dict[str, Any]]:
        if not self.process or not self.process.stdout or not self.process.stderr:
            raise AppServerError("app-server process is not running")

        notifications: list[dict[str, Any]] = []
        deadline = time.monotonic() + window_seconds
        while time.monotonic() < deadline:
            ready, _, _ = select([self.process.stdout, self.process.stderr], [], [], 0.25)
            for stream in ready:
                line = stream.readline()
                if not line:
                    continue
                if stream is self.process.stderr:
                    self.stderr_line_count += 1
                    continue
                message = json.loads(line)
                if message.get("method") in methods:
                    notifications.append(message)
        return notifications


def codex_command() -> str:
    return os.environ.get("CODEX_BIN", "codex")


def app_server_command() -> list[str]:
    return [codex_command(), "app-server", "--stdio"]


def app_server_proxy_command() -> list[str]:
    return [codex_command(), "app-server", "proxy"]


def initialize(client: JsonRpcClient) -> dict[str, Any]:
    response, _ = client.request(
        "initialize",
        {
            "clientInfo": CLIENT_INFO,
            "capabilities": {"experimentalApi": True},
        },
    )
    if "error" in response:
        raise AppServerError(f"initialize failed: {response['error']}")
    return response["result"]


def stable_fingerprint(value: str | None) -> str | None:
    if not value:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def redact_thread(thread: dict[str, Any]) -> dict[str, Any]:
    return {
        "idFingerprint": stable_fingerprint(thread.get("id")),
        "status": thread.get("status"),
        "source": thread.get("source"),
        "threadSource": thread.get("threadSource"),
        "createdAt": thread.get("createdAt"),
        "updatedAt": thread.get("updatedAt"),
        "recencyAt": thread.get("recencyAt"),
        "hasName": bool(thread.get("name")),
        "hasPreview": bool(thread.get("preview")),
        "hasCwd": bool(thread.get("cwd")),
        "turnCount": len(thread.get("turns") or []),
    }


def redact_turn(turn: dict[str, Any]) -> dict[str, Any]:
    return {
        "idFingerprint": stable_fingerprint(turn.get("id")),
        "status": turn.get("status"),
        "startedAt": turn.get("startedAt"),
        "completedAt": turn.get("completedAt"),
        "durationMs": turn.get("durationMs"),
        "itemsView": turn.get("itemsView"),
        "itemCount": len(turn.get("items") or []),
        "hasError": bool(turn.get("error")),
        "error": redact_json(turn.get("error")) if turn.get("error") else None,
    }


def redact_json(value: Any) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            if key in {"text", "preview", "name", "cwd", "path", "title", "content"}:
                result[key] = REDACTED
            elif key in {"threadId", "clientUserMessageId", "id", "sessionId"} and isinstance(item, str):
                result[key] = {
                    "fingerprint": stable_fingerprint(item),
                }
            else:
                result[key] = redact_json(item)
        return result
    if isinstance(value, list):
        return [redact_json(item) for item in value]
    return value


def write_thread_selection_file(threads: list[dict[str, Any]], output_path: str) -> dict[str, Any]:
    path = Path(output_path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    selections = [
        {
            "index": index,
            "id": thread.get("id"),
            "idFingerprint": stable_fingerprint(thread.get("id")),
            "createdAt": thread.get("createdAt"),
            "updatedAt": thread.get("updatedAt"),
            "recencyAt": thread.get("recencyAt"),
        }
        for index, thread in enumerate(threads)
    ]
    path.write_text(json.dumps({"threads": selections}, indent=2, sort_keys=True) + "\n")
    return {
        "path": str(path),
        "threadCount": len(selections),
        "containsRawThreadIds": True,
    }


def load_thread_id_from_selection_file(
    selection_file: str,
    selection_index: int,
    confirm_fingerprint: str,
) -> str:
    path = Path(selection_file).expanduser().resolve()
    try:
        payload = json.loads(path.read_text())
    except OSError as error:
        raise AppServerError(f"cannot read thread selection file: {error}") from error
    except json.JSONDecodeError as error:
        raise AppServerError(f"cannot parse thread selection file: {error}") from error

    threads = payload.get("threads")
    if not isinstance(threads, list):
        raise AppServerError("thread selection file is missing a threads array")

    match = next(
        (
            thread
            for thread in threads
            if isinstance(thread, dict) and thread.get("index") == selection_index
        ),
        None,
    )
    if not match:
        raise AppServerError(f"thread selection file has no entry for index {selection_index}")

    thread_id = match.get("id")
    if not isinstance(thread_id, str) or not thread_id:
        raise AppServerError(f"thread selection index {selection_index} is missing a raw id")

    fingerprint = stable_fingerprint(thread_id)
    if fingerprint != confirm_fingerprint:
        raise AppServerError("confirmed thread fingerprint does not match selected thread id")

    return thread_id


def notification_matches_target(
    notification: dict[str, Any],
    thread_id: str | None,
    turn_id: str | None,
) -> bool:
    params = notification.get("params", {})
    notification_thread_id = params.get("threadId")
    if thread_id and notification_thread_id and notification_thread_id != thread_id:
        return False

    notification_turn_id = params.get("turn", {}).get("id")
    if turn_id and notification_turn_id and notification_turn_id != turn_id:
        return False

    return True


def select_thread_from_cwd(
    client: JsonRpcClient,
    cwd: str,
    select_index: int,
) -> dict[str, Any]:
    list_response, _ = client.request(
        "thread/list",
        {
            "archived": False,
            "cwd": str(Path(cwd).expanduser().resolve()),
            "limit": max(select_index + 1, 1),
            "sortKey": "recency_at",
            "sortDirection": "desc",
        },
    )
    if "error" in list_response:
        raise AppServerError(f"thread/list selection failed: {list_response['error']}")
    threads = list_response["result"].get("data", [])
    if select_index >= len(threads):
        raise AppServerError(f"thread/list returned {len(threads)} threads, cannot select index {select_index}")
    return threads[select_index]


def method_schema_summary(schema_dir: Path) -> dict[str, Any]:
    expected = [
        "ThreadListParams.json",
        "ThreadListResponse.json",
        "TurnStartParams.json",
        "TurnStartResponse.json",
        "TurnStartedNotification.json",
        "TurnCompletedNotification.json",
        "JSONRPCRequest.json",
        "JSONRPCResponse.json",
    ]
    missing = [name for name in expected if not (schema_dir / "v2" / name).exists() and not (schema_dir / name).exists()]
    return {
        "schemaDir": str(schema_dir),
        "missingExpectedFiles": missing,
        "expectedFilesPresent": not missing,
    }


def command_summary(command: list[str], timeout: float) -> dict[str, Any]:
    try:
        completed = subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return {
            "command": " ".join(command),
            "status": "failed",
            "errorCategory": "timeout",
        }

    summary: dict[str, Any] = {
        "command": " ".join(command),
        "status": "completed" if completed.returncode == 0 else "failed",
        "returnCode": completed.returncode,
        "stdoutLineCount": len(completed.stdout.splitlines()),
        "stderrLineCount": len(completed.stderr.splitlines()),
    }
    if completed.stdout.strip().startswith("{"):
        try:
            summary["stdoutJSON"] = redact_json(json.loads(completed.stdout))
        except json.JSONDecodeError:
            summary["stdoutJSONParseError"] = True
    if completed.returncode != 0 and completed.stderr:
        summary["errorCategory"] = "stderr"
    return summary


def command_schema(args: argparse.Namespace) -> int:
    out_dir = Path(args.out).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    command = [
        codex_command(),
        "app-server",
        "generate-json-schema",
        "--experimental",
        "--out",
        str(out_dir),
    ]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        print(completed.stderr.strip(), file=sys.stderr)
        return completed.returncode

    summary = method_schema_summary(out_dir)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["expectedFilesPresent"] else 1


def command_list(args: argparse.Namespace) -> int:
    params: dict[str, Any] = {
        "archived": args.archived,
        "limit": args.limit,
        "sortKey": "recency_at",
        "sortDirection": "desc",
    }
    if args.cwd:
        params["cwd"] = str(Path(args.cwd).expanduser().resolve())

    with JsonRpcClient(app_server_command(), args.timeout) as client:
        init_result = initialize(client)
        response, notifications = client.request("thread/list", params)

    if "error" in response:
        result = {
            "status": "failed",
            "method": "thread/list",
            "error": response["error"],
            "notifications": [item.get("method") for item in notifications],
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

    threads = response["result"].get("data", [])
    result = {
        "status": "completed",
        "method": "thread/list",
        "server": {
            "userAgent": init_result.get("userAgent"),
            "platformOs": init_result.get("platformOs"),
            "platformFamily": init_result.get("platformFamily"),
        },
        "requestShape": redact_json(params),
        "threadCount": len(threads),
        "nextCursorPresent": bool(response["result"].get("nextCursor")),
        "threadFieldKeys": sorted(threads[0].keys()) if threads else [],
        "threads": [redact_thread(thread) for thread in threads],
        "notifications": [item.get("method") for item in notifications],
        "appServerStderrLineCount": client.stderr_line_count,
    }
    if args.selection_out:
        result["selectionFile"] = write_thread_selection_file(threads, args.selection_out)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def delivery_state_from_response(response: dict[str, Any]) -> tuple[str, str | None]:
    if "error" in response:
        return "failed", None

    turn = response.get("result", {}).get("turn")
    if not isinstance(turn, dict):
        return "requestAccepted", None

    turn_id = turn.get("id")
    status = turn.get("status")
    if status == "completed":
        return "completed", turn_id
    if status == "failed":
        return "failed", turn_id
    if status in {"inProgress", "interrupted"}:
        return "turnStarted", turn_id
    return "requestAccepted", turn_id


def make_delivery_attempt(
    packet_id: str,
    attempt_id: str,
    thread_id: str,
    client_user_message_id: str,
) -> dict[str, Any]:
    now = time.time()
    return {
        "id": attempt_id,
        "packetId": packet_id,
        "destination": "codexAppServer",
        "targetId": thread_id,
        "clientUserMessageId": client_user_message_id,
        "status": "queued",
        "startedAt": now,
        "updatedAt": now,
        "completedAt": None,
        "remoteTurnId": None,
        "errorCode": None,
        "errorMessage": None,
        "rawErrorJSON": None,
    }


def update_attempt_status(
    attempt: dict[str, Any],
    status: str,
    *,
    turn_id: str | None = None,
    error_code: str | None = None,
    error_message: str | None = None,
    raw_error: Any = None,
) -> None:
    attempt["status"] = status
    attempt["updatedAt"] = time.time()
    if status in {"completed", "failed"}:
        attempt["completedAt"] = attempt["updatedAt"]
    if turn_id:
        attempt["remoteTurnId"] = turn_id
    if error_code:
        attempt["errorCode"] = error_code
    if error_message:
        attempt["errorMessage"] = error_message
    if raw_error is not None:
        attempt["rawErrorJSON"] = json.dumps(redact_json(raw_error), sort_keys=True)


def redact_attempt(attempt: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": attempt["id"],
        "packetIdFingerprint": stable_fingerprint(attempt.get("packetId")),
        "destination": attempt["destination"],
        "targetIdFingerprint": stable_fingerprint(attempt.get("targetId")),
        "clientUserMessageIdFingerprint": stable_fingerprint(attempt.get("clientUserMessageId")),
        "status": attempt["status"],
        "startedAt": attempt["startedAt"],
        "updatedAt": attempt["updatedAt"],
        "completedAt": attempt["completedAt"],
        "remoteTurnIdFingerprint": stable_fingerprint(attempt.get("remoteTurnId")),
        "errorCode": attempt["errorCode"],
        "errorMessage": attempt["errorMessage"],
        "rawErrorJSON": attempt["rawErrorJSON"],
    }


def command_send(args: argparse.Namespace) -> int:
    if not args.live:
        print("Refusing live send: pass --live with --thread-id to call turn/start.", file=sys.stderr)
        return 2
    if not args.thread_id and not args.select_from_cwd:
        print("Refusing live send: pass --thread-id or --select-from-cwd.", file=sys.stderr)
        return 2
    if args.select_from_cwd and not args.cwd:
        print("Refusing live send: --select-from-cwd requires --cwd.", file=sys.stderr)
        return 2
    if args.select_from_cwd and args.confirm_select_index != args.select_index:
        print("Refusing live send: --select-from-cwd requires --confirm-select-index to match --select-index.", file=sys.stderr)
        return 2
    if not args.message:
        print("Refusing live send: --message is required.", file=sys.stderr)
        return 2

    client_user_message_id = args.client_user_message_id or f"onpaper-spike:{int(time.time())}"
    timeline: list[dict[str, Any]] = [{"state": "queued", "at": time.time()}]
    selected_thread: dict[str, Any] | None = None

    with JsonRpcClient(app_server_command(), args.timeout) as client:
        init_result = initialize(client)
        thread_id = args.thread_id
        if args.select_from_cwd:
            selected_thread = select_thread_from_cwd(client, args.cwd, args.select_index)
            thread_id = selected_thread["id"]

        request_params: dict[str, Any] = {
            "threadId": thread_id,
            "clientUserMessageId": client_user_message_id,
            "input": [{"type": "text", "text": args.message}],
        }
        if args.cwd:
            request_params["cwd"] = str(Path(args.cwd).expanduser().resolve())
        if args.read_only:
            request_params["sandboxPolicy"] = {"type": "readOnly", "networkAccess": False}
            request_params["approvalPolicy"] = "never"

        response, notifications = client.request(
            "turn/start",
            request_params,
            collect_until={"turn/started", "turn/completed", "error"},
        )
        state, turn_id = delivery_state_from_response(response)
        timeline.append({"state": "requestAccepted" if "result" in response else "failed", "at": time.time()})
        if state in {"turnStarted", "completed"}:
            timeline.append({"state": "turnStarted", "turnIdFingerprint": stable_fingerprint(turn_id), "at": time.time()})
        elif state == "failed":
            timeline.append({"state": "failed", "at": time.time()})

        observed = notifications + client.collect_notifications(
            {"turn/started", "turn/completed", "error"},
            args.observe_seconds,
        )

    for notification in observed:
        if not notification_matches_target(notification, thread_id, turn_id):
            continue
        method = notification.get("method")
        turn = notification.get("params", {}).get("turn", {})
        notification_turn_id = turn.get("id")
        if method == "turn/started":
            turn_id = turn_id or notification_turn_id
            timeline.append(
                {
                    "state": "turnStarted",
                    "turnIdFingerprint": stable_fingerprint(notification_turn_id),
                    "at": time.time(),
                }
            )
        elif method == "turn/completed":
            turn_id = turn_id or notification_turn_id
            completed_state = "failed" if turn.get("status") == "failed" else "completed"
            timeline.append(
                {
                    "state": completed_state,
                    "turnIdFingerprint": stable_fingerprint(notification_turn_id),
                    "turnStatus": turn.get("status"),
                    "at": time.time(),
                }
            )
        elif method == "error":
            timeline.append({"state": "failed", "at": time.time()})

    final_state = next((item["state"] for item in reversed(timeline) if item["state"] in STATUS_EVENTS), "failed")
    filtered_observed = [
        item
        for item in observed
        if notification_matches_target(item, thread_id, turn_id)
    ]
    result = {
        "status": final_state,
        "method": "turn/start",
        "server": {
            "userAgent": init_result.get("userAgent"),
            "platformOs": init_result.get("platformOs"),
            "platformFamily": init_result.get("platformFamily"),
        },
        "selectedThread": redact_thread(selected_thread) if selected_thread else None,
        "request": redact_json({"method": "turn/start", "params": request_params}),
        "response": redact_json(response),
        "observedNotificationMethods": [item.get("method") for item in filtered_observed],
        "timeline": timeline,
        "appServerStderrLineCount": client.stderr_line_count,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if final_state in {"turnStarted", "completed"} else 1


def command_packet_delivery(args: argparse.Namespace) -> int:
    if not args.message:
        print("Refusing packet delivery: --message is required.", file=sys.stderr)
        return 2

    uses_raw_thread_id = bool(args.thread_id)
    uses_selection_file = bool(args.thread_selection_file)
    if uses_raw_thread_id and uses_selection_file:
        print("Refusing packet delivery: use either --thread-id or --thread-selection-file, not both.", file=sys.stderr)
        return 2

    if args.live and uses_raw_thread_id and args.confirm_thread_id != args.thread_id:
        print("Refusing live packet delivery: --confirm-thread-id must exactly match --thread-id.", file=sys.stderr)
        return 2
    if args.live and uses_selection_file:
        if args.thread_selection_index is None:
            print("Refusing live packet delivery: --thread-selection-index is required with --thread-selection-file.", file=sys.stderr)
            return 2
        if not args.confirm_thread_fingerprint:
            print("Refusing live packet delivery: --confirm-thread-fingerprint is required with --thread-selection-file.", file=sys.stderr)
            return 2
    if args.live and not uses_raw_thread_id and not uses_selection_file:
        print("Refusing live packet delivery: pass --thread-id or --thread-selection-file.", file=sys.stderr)
        return 2

    try:
        thread_id = args.thread_id or (
            load_thread_id_from_selection_file(
                args.thread_selection_file,
                args.thread_selection_index,
                args.confirm_thread_fingerprint,
            )
            if uses_selection_file
            else "<existing-thread-id>"
        )
    except AppServerError as error:
        print(f"Refusing packet delivery: {error}", file=sys.stderr)
        return 2

    attempt_id = args.attempt_id or f"attempt-{int(time.time())}"
    client_user_message_id = args.client_user_message_id or f"onpaper:{args.packet_id}:{attempt_id}"
    request_params: dict[str, Any] = {
        "threadId": thread_id,
        "clientUserMessageId": client_user_message_id,
        "input": [{"type": "text", "text": args.message}],
    }
    if args.cwd:
        request_params["cwd"] = str(Path(args.cwd).expanduser().resolve())
    if args.read_only:
        request_params["sandboxPolicy"] = {"type": "readOnly", "networkAccess": False}
        request_params["approvalPolicy"] = "never"

    attempt = make_delivery_attempt(args.packet_id, attempt_id, thread_id, client_user_message_id)
    timeline: list[dict[str, Any]] = [{"state": "queued", "at": attempt["startedAt"]}]
    response: dict[str, Any] | None = None
    observed: list[dict[str, Any]] = []
    init_result: dict[str, Any] = {}
    app_server_stderr_line_count: int | None = None

    if args.live:
        client: JsonRpcClient | None = None
        try:
            client = JsonRpcClient(app_server_command(), args.timeout)
            with client:
                init_result = initialize(client)
                response, notifications = client.request(
                    "turn/start",
                    request_params,
                    collect_until={"turn/started", "turn/completed", "error"},
                )
                observed = notifications + client.collect_notifications(
                    {"turn/started", "turn/completed", "error"},
                    args.observe_seconds,
                )
                app_server_stderr_line_count = client.stderr_line_count
        except AppServerError as error:
            update_attempt_status(
                attempt,
                "failed",
                error_code="transport",
                error_message=str(error),
                raw_error={"message": str(error)},
            )
            timeline.append({"state": "failed", "at": attempt["updatedAt"]})
        except OSError as error:
            update_attempt_status(
                attempt,
                "failed",
                error_code="process",
                error_message=str(error),
                raw_error={"message": str(error)},
            )
            timeline.append({"state": "failed", "at": attempt["updatedAt"]})

        if response is not None:
            if "error" in response:
                error = response["error"]
                update_attempt_status(
                    attempt,
                    "failed",
                    error_code=str(error.get("code")) if isinstance(error, dict) else None,
                    error_message=str(error.get("message")) if isinstance(error, dict) else str(error),
                    raw_error=error,
                )
                timeline.append({"state": "failed", "at": attempt["updatedAt"]})
            else:
                update_attempt_status(attempt, "requestAccepted")
                timeline.append({"state": "requestAccepted", "at": attempt["updatedAt"]})
                state, turn_id = delivery_state_from_response(response)
                if state == "turnStarted":
                    update_attempt_status(attempt, "turnStarted", turn_id=turn_id)
                    timeline.append(
                        {
                            "state": "turnStarted",
                            "turnIdFingerprint": stable_fingerprint(turn_id),
                            "at": attempt["updatedAt"],
                        }
                    )
                elif state == "completed":
                    update_attempt_status(attempt, "completed", turn_id=turn_id)
                    timeline.append(
                        {
                            "state": "completed",
                            "turnIdFingerprint": stable_fingerprint(turn_id),
                            "at": attempt["updatedAt"],
                        }
                    )

        for notification in observed:
            if not notification_matches_target(
                notification,
                thread_id,
                attempt.get("remoteTurnId"),
            ):
                continue
            method = notification.get("method")
            params = notification.get("params", {})
            turn = params.get("turn", {})
            notification_turn_id = turn.get("id")
            if method == "turn/started":
                update_attempt_status(attempt, "turnStarted", turn_id=notification_turn_id)
                timeline.append(
                    {
                        "state": "turnStarted",
                        "turnIdFingerprint": stable_fingerprint(notification_turn_id),
                        "at": attempt["updatedAt"],
                    }
                )
            elif method == "turn/completed":
                completed_state = "failed" if turn.get("status") == "failed" else "completed"
                update_attempt_status(attempt, completed_state, turn_id=notification_turn_id)
                timeline.append(
                    {
                        "state": completed_state,
                        "turnIdFingerprint": stable_fingerprint(notification_turn_id),
                        "turnStatus": turn.get("status"),
                        "at": attempt["updatedAt"],
                    }
                )
            elif method == "error":
                update_attempt_status(
                    attempt,
                    "failed",
                    error_code=params.get("code"),
                    error_message=params.get("message", "app-server error"),
                    raw_error=params,
                )
                timeline.append({"state": "failed", "at": attempt["updatedAt"]})

    result = {
        "status": attempt["status"],
        "method": "packet-delivery",
        "liveTurnSent": args.live,
        "manualThreadSelectionRequired": True,
        "server": {
            "userAgent": init_result.get("userAgent"),
            "platformOs": init_result.get("platformOs"),
            "platformFamily": init_result.get("platformFamily"),
        } if init_result else None,
        "packet": {
            "idFingerprint": stable_fingerprint(args.packet_id),
            "textByteCount": len(args.message.encode("utf-8")),
        },
        "attempt": redact_attempt(attempt),
        "request": redact_json({"method": "turn/start", "params": request_params}),
        "response": redact_json(response) if response is not None else None,
        "observedNotificationMethods": [
            item.get("method")
            for item in observed
            if notification_matches_target(item, thread_id, attempt.get("remoteTurnId"))
        ],
        "timeline": timeline,
        "appServerStderrLineCount": app_server_stderr_line_count,
        "safety": {
            "dryRunRequiresNoLiveFlag": not args.live,
            "liveRequiresThreadIdConfirmation": True,
            "liveSupportsSelectionFileFingerprintConfirmation": True,
            "textRedactedFromOutput": True,
        },
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if attempt["status"] != "failed" else 1


def command_turns(args: argparse.Namespace) -> int:
    if not args.thread_id and not args.select_from_cwd:
        print("Refusing turn inspection: pass --thread-id or --select-from-cwd.", file=sys.stderr)
        return 2
    if args.select_from_cwd and not args.cwd:
        print("Refusing turn inspection: --select-from-cwd requires --cwd.", file=sys.stderr)
        return 2

    selected_thread: dict[str, Any] | None = None
    with JsonRpcClient(app_server_command(), args.timeout) as client:
        init_result = initialize(client)
        thread_id = args.thread_id
        if args.select_from_cwd:
            selected_thread = select_thread_from_cwd(client, args.cwd, args.select_index)
            thread_id = selected_thread["id"]

        response, notifications = client.request(
            "thread/turns/list",
            {
                "threadId": thread_id,
                "limit": args.limit,
                "sortDirection": "desc",
                "itemsView": "notLoaded",
            },
        )

    if "error" in response:
        result = {
            "status": "failed",
            "method": "thread/turns/list",
            "selectedThread": redact_thread(selected_thread) if selected_thread else None,
            "error": response["error"],
            "notifications": [item.get("method") for item in notifications],
            "appServerStderrLineCount": client.stderr_line_count,
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

    turns = response["result"].get("data", [])
    result = {
        "status": "completed",
        "method": "thread/turns/list",
        "server": {
            "userAgent": init_result.get("userAgent"),
            "platformOs": init_result.get("platformOs"),
            "platformFamily": init_result.get("platformFamily"),
        },
        "selectedThread": redact_thread(selected_thread) if selected_thread else None,
        "turnCount": len(turns),
        "turns": [redact_turn(turn) for turn in turns],
        "notifications": [item.get("method") for item in notifications],
        "appServerStderrLineCount": client.stderr_line_count,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def command_daemon_proxy(args: argparse.Namespace) -> int:
    checks: list[dict[str, Any]] = []

    if not args.skip_start:
        checks.append(command_summary([codex_command(), "app-server", "daemon", "start"], args.command_timeout))

    checks.append(command_summary([codex_command(), "app-server", "daemon", "version"], args.command_timeout))

    proxy_result: dict[str, Any] = {
        "command": " ".join(app_server_proxy_command()),
        "operation": "initialize",
    }
    client: JsonRpcClient | None = None
    try:
        client = JsonRpcClient(app_server_proxy_command(), args.timeout)
        with client:
            init_result = initialize(client)
            proxy_result.update(
                {
                    "status": "completed",
                    "server": {
                        "userAgent": init_result.get("userAgent"),
                        "platformOs": init_result.get("platformOs"),
                        "platformFamily": init_result.get("platformFamily"),
                    },
                    "appServerStderrLineCount": client.stderr_line_count,
                }
            )
    except AppServerError as error:
        proxy_result.update(
            {
                "status": "failed",
                "errorCategory": "jsonRpcOrTransport",
                "errorMessage": str(error),
                "appServerStderrLineCount": client.stderr_line_count if client else None,
            }
        )
    checks.append(proxy_result)

    status = "completed" if all(check.get("status") == "completed" for check in checks) else "failed"
    result = {
        "status": status,
        "method": "daemon-proxy",
        "liveTurnSent": False,
        "checks": checks,
        "conclusion": (
            "daemon/proxy accepts JSON-RPC initialize without sending a live turn"
            if status == "completed"
            else "daemon/proxy did not complete all safe checks"
        ),
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "completed" else 1


def command_doctor(_: argparse.Namespace) -> int:
    codex = shutil.which(codex_command())
    if not codex:
        print(json.dumps({"status": "failed", "error": "codex binary not found"}, indent=2))
        return 1
    version = subprocess.run([codex, "--version"], text=True, capture_output=True, check=False)
    result = {
        "status": "completed" if version.returncode == 0 else "failed",
        "codexPath": codex,
        "codexVersion": version.stdout.strip(),
        "appServerCommand": " ".join(app_server_command()),
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if version.returncode == 0 else version.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Codex app-server text turn spike.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor", help="Print installed Codex CLI/app-server basics.")
    doctor.set_defaults(func=command_doctor)

    schema = subparsers.add_parser("schema", help="Generate the installed app-server JSON schema.")
    schema.add_argument("--out", default=".onpaper-spike/codex-schema", help="Output directory for generated schema.")
    schema.set_defaults(func=command_schema)

    list_threads = subparsers.add_parser("list", help="Call thread/list and print redacted evidence.")
    list_threads.add_argument("--limit", type=int, default=10)
    list_threads.add_argument("--cwd", help="Optional cwd filter. The path is not printed.")
    list_threads.add_argument("--archived", action="store_true")
    list_threads.add_argument(
        "--selection-out",
        help="Optional ignored local JSON file that receives raw thread ids for human selection.",
    )
    list_threads.add_argument("--timeout", type=float, default=20)
    list_threads.set_defaults(func=command_list)

    send = subparsers.add_parser("send", help="Call turn/start with text input. Requires --live.")
    send.add_argument("--live", action="store_true", help="Required safety gate for a real send.")
    send.add_argument("--thread-id", required=False, help="Existing Codex thread id.")
    send.add_argument("--select-from-cwd", action="store_true", help="Select an existing thread from --cwd.")
    send.add_argument("--select-index", type=int, default=0, help="Zero-based index from the cwd-filtered thread list.")
    send.add_argument("--confirm-select-index", type=int, help="Required with --select-from-cwd to confirm the chosen index.")
    send.add_argument("--message", required=False, help="Text-only spike message to send.")
    send.add_argument("--client-user-message-id", required=False)
    send.add_argument("--cwd", help="Optional cwd override. The path is redacted from output.")
    send.add_argument("--read-only", action="store_true", help="Request a read-only/no-approval turn.")
    send.add_argument("--timeout", type=float, default=30)
    send.add_argument("--observe-seconds", type=float, default=15)
    send.set_defaults(func=command_send)

    packet_delivery = subparsers.add_parser(
        "packet-delivery",
        help="Build a DeliveryAttempt-shaped text packet delivery; live mode requires explicit thread id confirmation.",
    )
    packet_delivery.add_argument("--live", action="store_true", help="Actually call turn/start.")
    packet_delivery.add_argument("--packet-id", default="issue-6-live-spike")
    packet_delivery.add_argument("--attempt-id", required=False)
    packet_delivery.add_argument("--thread-id", required=False, help="Existing Codex thread id. Required with --live.")
    packet_delivery.add_argument(
        "--confirm-thread-id",
        required=False,
        help="Must exactly match --thread-id with --live.",
    )
    packet_delivery.add_argument(
        "--thread-selection-file",
        required=False,
        help="Ignored local selection JSON written by list --selection-out.",
    )
    packet_delivery.add_argument(
        "--thread-selection-index",
        type=int,
        required=False,
        help="Selected index from --thread-selection-file.",
    )
    packet_delivery.add_argument(
        "--confirm-thread-fingerprint",
        required=False,
        help="Must match the selected idFingerprint from --thread-selection-file with --live.",
    )
    packet_delivery.add_argument("--message", required=False, help="Text-only rendered packet body.")
    packet_delivery.add_argument("--client-user-message-id", required=False)
    packet_delivery.add_argument("--cwd", help="Optional cwd override. The path is redacted from output.")
    packet_delivery.add_argument("--read-only", action="store_true", help="Request a read-only/no-approval turn.")
    packet_delivery.add_argument("--timeout", type=float, default=30)
    packet_delivery.add_argument("--observe-seconds", type=float, default=15)
    packet_delivery.set_defaults(func=command_packet_delivery)

    turns = subparsers.add_parser("turns", help="Inspect recent turn statuses without item contents.")
    turns.add_argument("--thread-id", required=False, help="Existing Codex thread id.")
    turns.add_argument("--select-from-cwd", action="store_true", help="Select an existing thread from --cwd.")
    turns.add_argument("--select-index", type=int, default=0, help="Zero-based index from the cwd-filtered thread list.")
    turns.add_argument("--cwd", help="Required when using --select-from-cwd. The path is not printed.")
    turns.add_argument("--limit", type=int, default=5)
    turns.add_argument("--timeout", type=float, default=20)
    turns.set_defaults(func=command_turns)

    daemon_proxy = subparsers.add_parser(
        "daemon-proxy",
        help="Start/check daemon and probe proxy initialize without sending a turn.",
    )
    daemon_proxy.add_argument("--skip-start", action="store_true", help="Do not run daemon start first.")
    daemon_proxy.add_argument("--command-timeout", type=float, default=20)
    daemon_proxy.add_argument("--timeout", type=float, default=20)
    daemon_proxy.set_defaults(func=command_daemon_proxy)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
