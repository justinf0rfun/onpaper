import Foundation

public enum PacketIntent: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case debug
    case implement
    case review
    case explain
}

public struct ContextPacket: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var goal: String
    public var intent: PacketIntent
    public var assetIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        goal: String,
        intent: PacketIntent,
        assetIDs: [UUID],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.goal = goal
        self.intent = intent
        self.assetIDs = assetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ContextPacketDraft: Equatable, Sendable {
    public var goal: String
    public var intent: PacketIntent
    public var assetIDs: [UUID]

    public init(goal: String, intent: PacketIntent, assetIDs: [UUID]) {
        self.goal = goal
        self.intent = intent
        self.assetIDs = assetIDs
    }
}

public protocol ContextPacketStoring: Sendable {
    func create(_ draft: ContextPacketDraft, id: UUID, now: Date) async throws -> ContextPacket
    func latest() async throws -> ContextPacket?
    func resolve(_ id: UUID) async throws -> ContextPacket?
}

public actor FileBackedContextPacketStore: ContextPacketStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func create(_ draft: ContextPacketDraft, id: UUID = UUID(), now: Date = Date()) async throws -> ContextPacket {
        let packet = ContextPacket(
            id: id,
            goal: normalizePacketGoal(draft.goal),
            intent: draft.intent,
            assetIDs: draft.assetIDs,
            createdAt: now,
            updatedAt: now
        )
        var packets = try loadPackets()
        packets.append(packet)
        try writePackets(packets)
        return packet
    }

    public func latest() async throws -> ContextPacket? {
        try loadPackets()
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }

    public func resolve(_ id: UUID) async throws -> ContextPacket? {
        try loadPackets().first { $0.id == id }
    }

    private func loadPackets() throws -> [ContextPacket] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([ContextPacket].self, from: data)
    }

    private func writePackets(_ packets: [ContextPacket]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(packets)
        try data.write(to: fileURL, options: .atomic)
    }
}

public struct RenderedPacketPreview: Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ContextPacketComposer: Sendable {
    private var assetStore: any ContextAssetStoring
    private var packetStore: any ContextPacketStoring
    private var renderer: ContextPacketPreviewRenderer
    private var now: @Sendable () -> Date
    private var makeID: @Sendable () -> UUID

    public init(
        assetStore: any ContextAssetStoring,
        packetStore: any ContextPacketStoring,
        renderer: ContextPacketPreviewRenderer = ContextPacketPreviewRenderer(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.assetStore = assetStore
        self.packetStore = packetStore
        self.renderer = renderer
        self.now = now
        self.makeID = makeID
    }

    public func createDraft(goal: String, intent: PacketIntent, assetIDs: [UUID]) async throws -> ContextPacket {
        for id in assetIDs {
            guard try await assetStore.resolve(id) != nil else {
                throw ContextPacketComposerError.missingAsset(id)
            }
        }
        let packet = try await packetStore.create(
            ContextPacketDraft(goal: goal, intent: intent, assetIDs: assetIDs),
            id: makeID(),
            now: now()
        )
        return packet
    }

    public func render(_ packet: ContextPacket) async throws -> RenderedPacketPreview {
        let assets = try await resolveAssets(for: packet)
        return renderer.render(packet: packet, assets: assets)
    }

    private func resolveAssets(for packet: ContextPacket) async throws -> [ContextAsset] {
        var assets: [ContextAsset] = []
        for id in packet.assetIDs {
            guard let asset = try await assetStore.resolve(id) else {
                throw ContextPacketComposerError.missingAsset(id)
            }
            assets.append(asset)
        }
        return assets
    }
}

public enum ContextPacketComposerError: Error, Equatable, Sendable {
    case missingAsset(UUID)
}

public struct ContextPacketPreviewRenderer: Sendable {
    private var assetRenderer: ContextAssetCanonicalTextRenderer

    public init(assetRenderer: ContextAssetCanonicalTextRenderer = ContextAssetCanonicalTextRenderer()) {
        self.assetRenderer = assetRenderer
    }

    public func render(packet: ContextPacket, assets: [ContextAsset]) -> RenderedPacketPreview {
        let lines = [
            "Intent: \(packet.intent.rawValue)",
            "",
            "Goal:",
            packet.goal,
            "",
            "Context assets:"
        ] + assets.enumerated().flatMap { index, asset in
            assetLines(asset: asset, number: index + 1)
        } + [
            "",
            "Instructions:",
            "Use the attached context as source material. Preserve file paths and image references.",
            "If context is insufficient, ask before changing unrelated code."
        ]

        return RenderedPacketPreview(text: lines.joined(separator: "\n"))
    }

    private func assetLines(asset: ContextAsset, number: Int) -> [String] {
        var lines = [
            "\(number). [\(asset.kind.rawValue)] \(asset.title)"
        ]
        if let sourceName = asset.sourceApp?.name, !sourceName.isEmpty {
            lines.append("   Source: \(sourceName), captured \(formatDate(asset.capturedAt))")
        } else {
            lines.append("   Captured: \(formatDate(asset.capturedAt))")
        }
        lines.append("   Content:")
        lines.append(indent(assetRenderer.render(asset), prefix: "   "))
        return lines
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }

    private func indent(_ text: String, prefix: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + String($0) }
            .joined(separator: "\n")
    }
}

func normalizePacketGoal(_ goal: String) -> String {
    goal.trimmingCharacters(in: .whitespacesAndNewlines)
}
