import Foundation

public enum DeliveryAttemptStatus: String, Equatable, Sendable {
    case queued
    case requestAccepted
    case turnStarted
    case completed
    case failed
}

public struct CodexThreadListRequest: Equatable, Sendable {
    public var archived: Bool?
    public var limit: Int?
    public var sortKey: String
    public var sortDirection: String

    public init(
        archived: Bool? = false,
        limit: Int? = 30,
        sortKey: String = "recency_at",
        sortDirection: String = "desc"
    ) {
        self.archived = archived
        self.limit = limit
        self.sortKey = sortKey
        self.sortDirection = sortDirection
    }
}

public struct CodexThreadTarget: Equatable, Sendable {
    public var id: String
    public var label: String?

    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label
    }
}

public struct CodexThreadPage: Equatable, Sendable {
    public var threads: [CodexThreadTarget]
    public var nextCursor: String?

    public init(threads: [CodexThreadTarget], nextCursor: String? = nil) {
        self.threads = threads
        self.nextCursor = nextCursor
    }
}

public enum CodexUserInput: Equatable, Sendable {
    case text(String)
}

public struct CodexTurnStartRequest: Equatable, Sendable {
    public var threadId: String
    public var input: [CodexUserInput]
    public var clientUserMessageId: String

    public init(threadId: String, input: [CodexUserInput], clientUserMessageId: String) {
        self.threadId = threadId
        self.input = input
        self.clientUserMessageId = clientUserMessageId
    }
}

public enum CodexTurnStatus: String, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case interrupted
}

public struct CodexTurn: Equatable, Sendable {
    public var id: String
    public var status: CodexTurnStatus

    public init(id: String, status: CodexTurnStatus) {
        self.id = id
        self.status = status
    }
}

public struct CodexTurnStartResponse: Equatable, Sendable {
    public var turn: CodexTurn?

    public init(turn: CodexTurn? = nil) {
        self.turn = turn
    }
}

public enum CodexServerEvent: Equatable, Sendable {
    case turnStarted(threadId: String, turn: CodexTurn)
    case turnCompleted(threadId: String, turn: CodexTurn)
    case error(threadId: String?, code: String?, message: String, rawJSON: String?)
}

public struct CodexAppServerFailure: Error, Equatable, Sendable {
    public var code: String?
    public var message: String
    public var rawJSON: String?

    public init(code: String? = nil, message: String, rawJSON: String? = nil) {
        self.code = code
        self.message = message
        self.rawJSON = rawJSON
    }
}

public protocol CodexAppServerClient {
    func listThreads(_ request: CodexThreadListRequest) async throws -> CodexThreadPage
    func startTurn(_ request: CodexTurnStartRequest) async throws -> CodexTurnStartResponse
    func events() -> AsyncStream<CodexServerEvent>
}

public struct DeliveryAttempt: Equatable, Sendable {
    public var id: String
    public var packetId: String?
    public var destination: String
    public var targetId: String
    public var clientUserMessageId: String
    public var status: DeliveryAttemptStatus
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var remoteTurnId: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var rawErrorJSON: String?

    public init(
        id: String = UUID().uuidString,
        packetId: String? = nil,
        destination: String = "codexAppServer",
        targetId: String,
        clientUserMessageId: String,
        status: DeliveryAttemptStatus,
        startedAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        remoteTurnId: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        rawErrorJSON: String? = nil
    ) {
        self.id = id
        self.packetId = packetId
        self.destination = destination
        self.targetId = targetId
        self.clientUserMessageId = clientUserMessageId
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.remoteTurnId = remoteTurnId
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.rawErrorJSON = rawErrorJSON
    }
}

public struct CodexDeliveryStateMachine: Sendable {
    public private(set) var attempt: DeliveryAttempt

    public init(attempt: DeliveryAttempt) {
        self.attempt = attempt
    }

    public init(targetId: String, clientUserMessageId: String, now: Date = Date()) {
        self.attempt = DeliveryAttempt(
            targetId: targetId,
            clientUserMessageId: clientUserMessageId,
            status: .queued,
            startedAt: now,
            updatedAt: now
        )
    }

    public mutating func applyStartResponse(_ response: CodexTurnStartResponse, now: Date = Date()) {
        guard let turn = response.turn else {
            setStatus(.requestAccepted, now: now)
            return
        }

        attempt.remoteTurnId = turn.id
        switch turn.status {
        case .inProgress, .interrupted:
            setStatus(.turnStarted, now: now)
        case .completed:
            setStatus(.completed, now: now, completedAt: now)
        case .failed:
            setStatus(.failed, now: now, completedAt: now)
        }
    }

    public mutating func applyEvent(_ event: CodexServerEvent, now: Date = Date()) {
        switch event {
        case let .turnStarted(threadId, turn):
            guard threadId == attempt.targetId else { return }
            attempt.remoteTurnId = turn.id
            setStatus(.turnStarted, now: now)
        case let .turnCompleted(threadId, turn):
            guard threadId == attempt.targetId else { return }
            attempt.remoteTurnId = turn.id
            switch turn.status {
            case .completed:
                setStatus(.completed, now: now, completedAt: now)
            case .failed, .interrupted:
                setStatus(.failed, now: now, completedAt: now)
            case .inProgress:
                setStatus(.turnStarted, now: now)
            }
        case let .error(threadId, code, message, rawJSON):
            guard threadId == nil || threadId == attempt.targetId else { return }
            attempt.errorCode = code
            attempt.errorMessage = message
            attempt.rawErrorJSON = rawJSON
            setStatus(.failed, now: now, completedAt: now)
        }
    }

    public mutating func applyFailure(_ failure: CodexAppServerFailure, now: Date = Date()) {
        attempt.errorCode = failure.code
        attempt.errorMessage = failure.message
        attempt.rawErrorJSON = failure.rawJSON
        setStatus(.failed, now: now, completedAt: now)
    }

    private mutating func setStatus(
        _ status: DeliveryAttemptStatus,
        now: Date,
        completedAt: Date? = nil
    ) {
        attempt.status = status
        attempt.updatedAt = now
        if let completedAt {
            attempt.completedAt = completedAt
        }
    }
}

public struct CodexAppServerDestination {
    private var client: CodexAppServerClient
    private var now: @Sendable () -> Date

    public init(client: CodexAppServerClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func listThreads(_ request: CodexThreadListRequest = CodexThreadListRequest()) async throws -> CodexThreadPage {
        try await client.listThreads(request)
    }

    public func startTextTurn(
        threadId: String,
        text: String,
        clientUserMessageId: String
    ) async -> DeliveryAttempt {
        let request = CodexTurnStartRequest(
            threadId: threadId,
            input: [.text(text)],
            clientUserMessageId: clientUserMessageId
        )
        var stateMachine = CodexDeliveryStateMachine(
            targetId: threadId,
            clientUserMessageId: clientUserMessageId,
            now: now()
        )

        do {
            let response = try await client.startTurn(request)
            stateMachine.applyStartResponse(response, now: now())
        } catch let failure as CodexAppServerFailure {
            stateMachine.applyFailure(failure, now: now())
            return stateMachine.attempt
        } catch {
            stateMachine.applyFailure(
                CodexAppServerFailure(message: String(describing: error)),
                now: now()
            )
            return stateMachine.attempt
        }

        for await event in client.events() {
            stateMachine.applyEvent(event, now: now())
            if stateMachine.attempt.status == .completed || stateMachine.attempt.status == .failed {
                break
            }
        }

        return stateMachine.attempt
    }
}
