import Foundation

public struct RenderedPacket: Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ContextPacket: Equatable, Sendable {
    public var id: String
    public var renderedPacket: RenderedPacket

    public init(id: String, renderedPacket: RenderedPacket) {
        self.id = id
        self.renderedPacket = renderedPacket
    }
}

public enum PacketDeliveryStatus: String, Equatable, Sendable {
    case draft
    case pending
    case delivered
    case failed
}

public actor InMemoryDeliveryAttemptRepository {
    private var attempts: [DeliveryAttempt] = []
    private var nextAttemptNumber = 1

    public init() {}

    public func createQueuedAttempt(
        packetId: String,
        targetId: String,
        destination: String = "codexAppServer",
        now: Date = Date()
    ) -> DeliveryAttempt {
        let attemptId = "attempt-\(nextAttemptNumber)"
        nextAttemptNumber += 1
        let clientUserMessageId = "onpaper:\(packetId):\(attemptId)"
        let attempt = DeliveryAttempt(
            id: attemptId,
            packetId: packetId,
            destination: destination,
            targetId: targetId,
            clientUserMessageId: clientUserMessageId,
            status: .queued,
            startedAt: now,
            updatedAt: now
        )
        attempts.append(attempt)
        return attempt
    }

    public func update(_ attempt: DeliveryAttempt) {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }) else {
            attempts.append(attempt)
            return
        }
        attempts[index] = attempt
    }

    public func attempts(for packetId: String) -> [DeliveryAttempt] {
        attempts.filter { $0.packetId == packetId }
    }

    public func latestAttempt(for packetId: String) -> DeliveryAttempt? {
        attempts.last { $0.packetId == packetId }
    }

    public func status(for packetId: String) -> PacketDeliveryStatus {
        guard let latest = latestAttempt(for: packetId) else {
            return .draft
        }

        switch latest.status {
        case .queued, .requestAccepted, .turnStarted:
            return .pending
        case .completed:
            return .delivered
        case .failed:
            return .failed
        }
    }
}

public struct CodexPacketDeliveryCoordinator {
    private var client: CodexAppServerClient
    private var attempts: InMemoryDeliveryAttemptRepository
    private var now: @Sendable () -> Date

    public init(
        client: CodexAppServerClient,
        attempts: InMemoryDeliveryAttemptRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.attempts = attempts
        self.now = now
    }

    public func listTargets(_ request: CodexThreadListRequest = CodexThreadListRequest()) async throws -> CodexThreadPage {
        try await client.listThreads(request)
    }

    public func deliver(_ packet: ContextPacket, to target: CodexThreadTarget) async -> DeliveryAttempt {
        let queuedAttempt = await attempts.createQueuedAttempt(
            packetId: packet.id,
            targetId: target.id,
            now: now()
        )
        var stateMachine = CodexDeliveryStateMachine(attempt: queuedAttempt)

        do {
            let response = try await client.startTurn(
                CodexTurnStartRequest(
                    threadId: target.id,
                    input: [.text(packet.renderedPacket.text)],
                    clientUserMessageId: queuedAttempt.clientUserMessageId
                )
            )
            stateMachine.applyStartResponse(response, now: now())
        } catch let failure as CodexAppServerFailure {
            stateMachine.applyFailure(failure, now: now())
            await attempts.update(stateMachine.attempt)
            return stateMachine.attempt
        } catch {
            stateMachine.applyFailure(
                CodexAppServerFailure(message: String(describing: error)),
                now: now()
            )
            await attempts.update(stateMachine.attempt)
            return stateMachine.attempt
        }

        for await event in client.events() {
            stateMachine.applyEvent(event, now: now())
            if stateMachine.attempt.status == .completed || stateMachine.attempt.status == .failed {
                break
            }
        }

        await attempts.update(stateMachine.attempt)
        return stateMachine.attempt
    }
}
