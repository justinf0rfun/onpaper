import XCTest
@testable import OnPaperDestinations

final class CodexPacketDeliveryTests: XCTestCase {
    func testListsFakeTargetsThroughCoordinator() async throws {
        let client = ScriptedCodexAppServerClient(
            threads: [CodexThreadTarget(id: "thread-1", label: "Thread 1")]
        )
        let repository = InMemoryDeliveryAttemptRepository()
        let coordinator = CodexPacketDeliveryCoordinator(client: client, attempts: repository)

        let page = try await coordinator.listTargets()

        XCTAssertEqual(page.threads, [CodexThreadTarget(id: "thread-1", label: "Thread 1")])
    }

    func testCreatesQueuedAttemptBeforeRemoteDeliveryBegins() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))
        let client = ScriptedCodexAppServerClient(
            startResponses: [CodexTurnStartResponse()],
            onStart: { request in
                let attempts = await repository.attempts(for: "packet-1")
                XCTAssertEqual(attempts.count, 1)
                XCTAssertEqual(attempts[0].status, .queued)
                XCTAssertEqual(attempts[0].targetId, request.threadId)
                XCTAssertEqual(attempts[0].clientUserMessageId, request.clientUserMessageId)
            }
        )
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )

        _ = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
    }

    func testSuccessPathReachesCompletedAndDerivesDeliveredPacketStatus() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let client = ScriptedCodexAppServerClient(
            startResponses: [
                CodexTurnStartResponse(turn: CodexTurn(id: "turn-1", status: .inProgress))
            ],
            eventScripts: [
                [.turnCompleted(threadId: "thread-1", turn: CodexTurn(id: "turn-1", status: .completed))]
            ]
        )
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))

        let attempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let packetStatus = await repository.status(for: "packet-1")

        XCTAssertEqual(attempt.status, DeliveryAttemptStatus.completed)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertEqual(packetStatus, .delivered)
    }

    func testJsonRpcFailureRecordsRawErrorAndDerivesFailedPacketStatus() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let client = ScriptedCodexAppServerClient(
            startFailures: [
                CodexAppServerFailure(
                    code: "-32602",
                    message: "Invalid params",
                    rawJSON: #"{"code":-32602,"message":"Invalid params"}"#
                )
            ]
        )
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))

        let attempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let packetStatus = await repository.status(for: "packet-1")

        XCTAssertEqual(attempt.status, DeliveryAttemptStatus.failed)
        XCTAssertEqual(attempt.errorCode, "-32602")
        XCTAssertEqual(attempt.errorMessage, "Invalid params")
        XCTAssertEqual(attempt.rawErrorJSON, #"{"code":-32602,"message":"Invalid params"}"#)
        XCTAssertEqual(packetStatus, .failed)
    }

    func testRequestAcceptedWithoutCompletionRemainsPendingNotDelivered() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let client = ScriptedCodexAppServerClient(startResponses: [CodexTurnStartResponse()])
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))

        let attempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let packetStatus = await repository.status(for: "packet-1")

        XCTAssertEqual(attempt.status, DeliveryAttemptStatus.requestAccepted)
        XCTAssertEqual(packetStatus, .pending)
        XCTAssertNotEqual(packetStatus, .delivered)
    }

    func testTurnStartedWithoutCompletionRemainsPendingNotDelivered() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let client = ScriptedCodexAppServerClient(
            startResponses: [
                CodexTurnStartResponse(turn: CodexTurn(id: "turn-1", status: .inProgress))
            ]
        )
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))

        let attempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let packetStatus = await repository.status(for: "packet-1")

        XCTAssertEqual(attempt.status, DeliveryAttemptStatus.turnStarted)
        XCTAssertEqual(attempt.remoteTurnId, "turn-1")
        XCTAssertEqual(packetStatus, .pending)
        XCTAssertNotEqual(packetStatus, .delivered)
    }

    func testLatestAttemptDerivesPacketStatus() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let first = await repository.createQueuedAttempt(
            packetId: "packet-1",
            targetId: "thread-1",
            now: PacketTestClock().now()
        )
        var completed = first
        completed.status = .completed
        await repository.update(completed)

        let deliveredStatus = await repository.status(for: "packet-1")
        XCTAssertEqual(deliveredStatus, .delivered)

        let second = await repository.createQueuedAttempt(
            packetId: "packet-1",
            targetId: "thread-1",
            now: PacketTestClock().now()
        )
        var failed = second
        failed.status = .failed
        await repository.update(failed)

        let failedStatus = await repository.status(for: "packet-1")
        XCTAssertEqual(failedStatus, .failed)
    }

    func testRetryDoesNotOverwritePriorFailedAttempt() async {
        let repository = InMemoryDeliveryAttemptRepository()
        let client = ScriptedCodexAppServerClient(
            startResponses: [
                CodexTurnStartResponse(turn: CodexTurn(id: "turn-2", status: .inProgress))
            ],
            startFailures: [
                CodexAppServerFailure(
                    code: "transport",
                    message: "socket closed",
                    rawJSON: #"{"message":"socket closed"}"#
                )
            ],
            eventScripts: [
                [.turnCompleted(threadId: "thread-1", turn: CodexTurn(id: "turn-2", status: .completed))]
            ]
        )
        let coordinator = CodexPacketDeliveryCoordinator(
            client: client,
            attempts: repository,
            now: PacketTestClock().now
        )
        let packet = ContextPacket(id: "packet-1", renderedPacket: RenderedPacket(text: "hello"))

        let failedAttempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let completedAttempt = await coordinator.deliver(packet, to: CodexThreadTarget(id: "thread-1"))
        let attempts = await repository.attempts(for: "packet-1")

        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].id, failedAttempt.id)
        XCTAssertEqual(attempts[0].status, .failed)
        XCTAssertEqual(attempts[1].id, completedAttempt.id)
        XCTAssertEqual(attempts[1].status, .completed)
        XCTAssertNotEqual(attempts[0].id, attempts[1].id)
        let retryStatus = await repository.status(for: "packet-1")
        XCTAssertEqual(retryStatus, .delivered)
    }
}

private struct PacketTestClock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_783_245_000)
    }
}

private final class ScriptedCodexAppServerClient: CodexAppServerClient {
    private let threads: [CodexThreadTarget]
    private var startResponses: [CodexTurnStartResponse]
    private var startFailures: [CodexAppServerFailure]
    private var eventScripts: [[CodexServerEvent]]
    private let onStart: ((CodexTurnStartRequest) async -> Void)?

    init(
        threads: [CodexThreadTarget] = [],
        startResponses: [CodexTurnStartResponse] = [],
        startFailures: [CodexAppServerFailure] = [],
        eventScripts: [[CodexServerEvent]] = [],
        onStart: ((CodexTurnStartRequest) async -> Void)? = nil
    ) {
        self.threads = threads
        self.startResponses = startResponses
        self.startFailures = startFailures
        self.eventScripts = eventScripts
        self.onStart = onStart
    }

    func listThreads(_ request: CodexThreadListRequest) async throws -> CodexThreadPage {
        CodexThreadPage(threads: threads)
    }

    func startTurn(_ request: CodexTurnStartRequest) async throws -> CodexTurnStartResponse {
        await onStart?(request)
        if !startFailures.isEmpty {
            throw startFailures.removeFirst()
        }
        if !startResponses.isEmpty {
            return startResponses.removeFirst()
        }
        return CodexTurnStartResponse()
    }

    func events() -> AsyncStream<CodexServerEvent> {
        let events = eventScripts.isEmpty ? [] : eventScripts.removeFirst()
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
