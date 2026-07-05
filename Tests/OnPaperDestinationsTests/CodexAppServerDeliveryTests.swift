import XCTest
@testable import OnPaperDestinations

final class CodexAppServerDeliveryTests: XCTestCase {
    func testStateMachineStartsWithQueuedAttemptBeforeRemoteDelivery() {
        let stateMachine = CodexDeliveryStateMachine(
            targetId: "thread-1",
            clientUserMessageId: "message-1",
            now: FixedClock().now()
        )

        XCTAssertEqual(stateMachine.attempt.status, .queued)
        XCTAssertEqual(stateMachine.attempt.targetId, "thread-1")
        XCTAssertEqual(stateMachine.attempt.clientUserMessageId, "message-1")
        XCTAssertNil(stateMachine.attempt.remoteTurnId)
        XCTAssertNil(stateMachine.attempt.completedAt)
    }

    func testListsFakeCodexThreadTargetsThroughDestinationInterface() async throws {
        let client = FakeCodexAppServerClient(
            threads: [
                CodexThreadTarget(id: "thread-1", label: "Thread 1"),
                CodexThreadTarget(id: "thread-2", label: "Thread 2")
            ]
        )
        let destination = CodexAppServerDestination(client: client)

        let page = try await destination.listThreads(CodexThreadListRequest(limit: 2))

        XCTAssertEqual(page.threads.map(\.id), ["thread-1", "thread-2"])
        XCTAssertEqual(client.listRequests, [CodexThreadListRequest(limit: 2)])
    }

    func testTurnStartSuccessWithoutTurnObjectRecordsRequestAcceptedOnly() async {
        let client = FakeCodexAppServerClient(startResponse: CodexTurnStartResponse())
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .requestAccepted)
        XCTAssertEqual(attempt.targetId, "thread-1")
        XCTAssertEqual(attempt.clientUserMessageId, "message-1")
        XCTAssertEqual(attempt.destination, "codexAppServer")
        XCTAssertNil(attempt.completedAt)
        XCTAssertNil(attempt.remoteTurnId)
        XCTAssertEqual(client.startRequests, [
            CodexTurnStartRequest(threadId: "thread-1", input: [.text("hello")], clientUserMessageId: "message-1")
        ])
    }

    func testTurnStartResponseWithInProgressTurnRecordsTurnStarted() async {
        let client = FakeCodexAppServerClient(
            startResponse: CodexTurnStartResponse(turn: CodexTurn(id: "turn-1", status: .inProgress))
        )
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .turnStarted)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertNil(attempt.completedAt)
    }

    func testTurnStartedNotificationPromotesRequestAcceptedToTurnStarted() async {
        let client = FakeCodexAppServerClient(
            startResponse: CodexTurnStartResponse(),
            events: [
                .turnStarted(threadId: "thread-1", turn: CodexTurn(id: "turn-1", status: .inProgress))
            ]
        )
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .turnStarted)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertNil(attempt.completedAt)
    }

    func testTurnCompletedNotificationRecordsCompleted() async {
        let client = FakeCodexAppServerClient(
            startResponse: CodexTurnStartResponse(turn: CodexTurn(id: "turn-1", status: .inProgress)),
            events: [
                .turnCompleted(threadId: "thread-1", turn: CodexTurn(id: "turn-1", status: .completed))
            ]
        )
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .completed)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertNotNil(attempt.completedAt)
    }

    func testTurnCompletedNotificationWithFailedTurnRecordsFailed() async {
        let client = FakeCodexAppServerClient(
            startResponse: CodexTurnStartResponse(turn: CodexTurn(id: "turn-1", status: .inProgress)),
            events: [
                .turnCompleted(threadId: "thread-1", turn: CodexTurn(id: "turn-1", status: .failed))
            ]
        )
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertNotNil(attempt.completedAt)
    }

    func testJsonRpcErrorRecordsFailedAttemptWithRawErrorDetails() async {
        let client = FakeCodexAppServerClient(
            startError: CodexAppServerFailure(
                code: "-32602",
                message: "Invalid params",
                rawJSON: #"{"code":-32602,"message":"Invalid params"}"#
            )
        )
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.errorCode, "-32602")
        XCTAssertEqual(attempt.errorMessage, "Invalid params")
        XCTAssertEqual(attempt.rawErrorJSON, #"{"code":-32602,"message":"Invalid params"}"#)
        XCTAssertNotNil(attempt.completedAt)
    }

    func testRequestAcceptedWithoutCompletionRemainsPendingNotDelivered() async {
        let client = FakeCodexAppServerClient(startResponse: CodexTurnStartResponse())
        let destination = CodexAppServerDestination(client: client, now: FixedClock().now)

        let attempt = await destination.startTextTurn(
            threadId: "thread-1",
            text: "hello",
            clientUserMessageId: "message-1"
        )

        XCTAssertEqual(attempt.status, .requestAccepted)
        XCTAssertNotEqual(attempt.status, .completed)
        XCTAssertNil(attempt.completedAt)
    }
}

private final class FakeCodexAppServerClient: CodexAppServerClient {
    private let threads: [CodexThreadTarget]
    private let startResponse: CodexTurnStartResponse
    private let startError: CodexAppServerFailure?
    private let scriptedEvents: [CodexServerEvent]

    private(set) var listRequests: [CodexThreadListRequest] = []
    private(set) var startRequests: [CodexTurnStartRequest] = []

    init(
        threads: [CodexThreadTarget] = [],
        startResponse: CodexTurnStartResponse = CodexTurnStartResponse(),
        startError: CodexAppServerFailure? = nil,
        events: [CodexServerEvent] = []
    ) {
        self.threads = threads
        self.startResponse = startResponse
        self.startError = startError
        self.scriptedEvents = events
    }

    func listThreads(_ request: CodexThreadListRequest) async throws -> CodexThreadPage {
        listRequests.append(request)
        return CodexThreadPage(threads: threads)
    }

    func startTurn(_ request: CodexTurnStartRequest) async throws -> CodexTurnStartResponse {
        startRequests.append(request)
        if let startError {
            throw startError
        }
        return startResponse
    }

    func events() -> AsyncStream<CodexServerEvent> {
        AsyncStream { continuation in
            for event in scriptedEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private struct FixedClock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_783_245_000)
    }
}
