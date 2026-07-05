import Foundation

public enum ContextAssetKind: String, CaseIterable, Equatable, Sendable {
    case text
    case code
    case log
    case image
    case file
    case url
}

extension ContextAssetKind: Codable {}

public struct SourceAppMetadata: Codable, Equatable, Sendable {
    public var name: String?
    public var bundleIdentifier: String?

    public init(name: String? = nil, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct ContextAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ContextAssetKind
    public var title: String
    public var preview: String
    public var content: String
    public var capturedAt: Date
    public var sourceApp: SourceAppMetadata?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: ContextAssetKind,
        title: String,
        preview: String,
        content: String,
        capturedAt: Date = Date(),
        sourceApp: SourceAppMetadata? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.content = content
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.metadata = metadata
    }
}

public struct ContextAssetDraft: Equatable, Sendable {
    public var kind: ContextAssetKind
    public var title: String
    public var preview: String
    public var content: String
    public var capturedAt: Date
    public var sourceApp: SourceAppMetadata?
    public var metadata: [String: String]

    public init(
        kind: ContextAssetKind,
        title: String,
        preview: String,
        content: String,
        capturedAt: Date = Date(),
        sourceApp: SourceAppMetadata? = nil,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.title = title
        self.preview = preview
        self.content = content
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.metadata = metadata
    }
}

public protocol ContextAssetStoring: Sendable {
    func create(_ draft: ContextAssetDraft, id: UUID) async throws -> ContextAsset
    func recent(limit: Int) async throws -> [ContextAsset]
    func resolve(_ id: UUID) async throws -> ContextAsset?
    func delete(_ id: UUID) async throws
}

public actor FileBackedContextAssetStore: ContextAssetStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func create(_ draft: ContextAssetDraft, id: UUID = UUID()) async throws -> ContextAsset {
        let asset = ContextAsset(
            id: id,
            kind: draft.kind,
            title: draft.title,
            preview: draft.preview,
            content: draft.content,
            capturedAt: draft.capturedAt,
            sourceApp: draft.sourceApp,
            metadata: draft.metadata
        )
        var assets = try loadAssets()
        assets.append(asset)
        try writeAssets(assets)
        return asset
    }

    public func recent(limit: Int = 20) async throws -> [ContextAsset] {
        let assets = try loadAssets()
            .sorted { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.capturedAt > rhs.capturedAt
            }
        return Array(assets.prefix(max(limit, 0)))
    }

    public func resolve(_ id: UUID) async throws -> ContextAsset? {
        try loadAssets().first { $0.id == id }
    }

    public func delete(_ id: UUID) async throws {
        let assets = try loadAssets().filter { $0.id != id }
        try writeAssets(assets)
    }

    private func loadAssets() throws -> [ContextAsset] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([ContextAsset].self, from: data)
    }

    private func writeAssets(_ assets: [ContextAsset]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(assets)
        try data.write(to: fileURL, options: .atomic)
    }
}

public protocol ClipboardTextReading: Sendable {
    func currentString() -> String?
}

public protocol SourceAppMetadataProviding: Sendable {
    func currentSourceAppMetadata() -> SourceAppMetadata?
}

public struct EmptySourceAppMetadataProvider: SourceAppMetadataProviding {
    public init() {}

    public func currentSourceAppMetadata() -> SourceAppMetadata? {
        nil
    }
}

public struct TextClipboardCaptureService<Reader: ClipboardTextReading, SourceProvider: SourceAppMetadataProviding>: Sendable {
    private var reader: Reader
    private var sourceProvider: SourceProvider
    private var store: any ContextAssetStoring
    private var now: @Sendable () -> Date
    private var makeID: @Sendable () -> UUID

    public init(
        reader: Reader,
        sourceProvider: SourceProvider,
        store: any ContextAssetStoring,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.reader = reader
        self.sourceProvider = sourceProvider
        self.store = store
        self.now = now
        self.makeID = makeID
    }

    public func captureCurrentClipboard() async throws -> ContextAsset? {
        guard let content = reader.currentString() else { return nil }
        guard let draft = ContextAssetDraft.textLike(
            content: content,
            capturedAt: now(),
            sourceApp: sourceProvider.currentSourceAppMetadata()
        ) else {
            return nil
        }
        return try await store.create(draft, id: makeID())
    }
}

public struct ContextAssetCanonicalTextRenderer: Sendable {
    public init() {}

    public func render(_ asset: ContextAsset) -> String {
        asset.content
    }
}

public extension ContextAssetDraft {
    static func textLike(
        content: String,
        capturedAt: Date = Date(),
        sourceApp: SourceAppMetadata? = nil
    ) -> ContextAssetDraft? {
        let normalized = normalizeCapturedText(content)
        guard !normalized.isEmpty else { return nil }
        return ContextAssetDraft(
            kind: classifyText(normalized),
            title: makeTitle(from: normalized),
            preview: makePreview(from: normalized),
            content: normalized,
            capturedAt: capturedAt,
            sourceApp: sourceApp,
            metadata: metadataForCapturedText(normalized)
        )
    }
}

public struct InMemoryCapturePreviewItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ContextAssetKind
    public var title: String
    public var preview: String
    public var content: String
    public var capturedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ContextAssetKind,
        title: String,
        preview: String,
        content: String,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.content = content
        self.capturedAt = capturedAt
    }
}

public struct CapturePreviewSnapshot: Equatable, Sendable {
    public var placeholder: String
    public var latestItem: InMemoryCapturePreviewItem?

    public init(
        placeholder: String = "No capture yet",
        latestItem: InMemoryCapturePreviewItem? = nil
    ) {
        self.placeholder = placeholder
        self.latestItem = latestItem
    }
}

public struct InMemoryCapturePreviewState: Equatable, Sendable {
    public private(set) var latestItem: InMemoryCapturePreviewItem?

    public init(latestItem: InMemoryCapturePreviewItem? = nil) {
        self.latestItem = latestItem
    }

    public var snapshot: CapturePreviewSnapshot {
        CapturePreviewSnapshot(latestItem: latestItem)
    }

    public mutating func captureText(
        _ content: String,
        capturedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        guard let draft = ContextAssetDraft.textLike(content: content, capturedAt: capturedAt) else { return }

        latestItem = InMemoryCapturePreviewItem(
            id: id,
            kind: draft.kind,
            title: draft.title,
            preview: draft.preview,
            content: draft.content,
            capturedAt: draft.capturedAt
        )
    }
}

func normalizeCapturedText(_ content: String) -> String {
    content.trimmingCharacters(in: .whitespacesAndNewlines)
}

func classifyText(_ content: String) -> ContextAssetKind {
    if let scheme = URL(string: content)?.scheme?.lowercased(),
        ["http", "https"].contains(scheme) {
        return .url
    }
    if content.localizedCaseInsensitiveContains("error")
        || content.localizedCaseInsensitiveContains("exception")
        || content.localizedCaseInsensitiveContains("failed") {
        return .log
    }
    if content.contains("func ") || content.contains("class ") || content.contains("struct ") {
        return .code
    }
    return .text
}

func makeTitle(from content: String) -> String {
    let firstLine = content
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init) ?? "Captured text"
    return truncated(firstLine, limit: 48)
}

func makePreview(from content: String) -> String {
    truncated(content.replacingOccurrences(of: "\n", with: " "), limit: 160)
}

private func metadataForCapturedText(_ content: String) -> [String: String] {
    guard classifyText(content) == .url, let url = URL(string: content) else { return [:] }
    var metadata: [String: String] = [:]
    if let host = url.host() {
        metadata["host"] = host
    }
    return metadata
}

func truncated(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    let end = value.index(value.startIndex, offsetBy: limit)
    return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}
