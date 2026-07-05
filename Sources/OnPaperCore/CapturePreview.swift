import Foundation

public enum ContextAssetKind: String, CaseIterable, Equatable, Sendable {
    case text
    case code
    case log
    case image
    case file
    case url
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
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        latestItem = InMemoryCapturePreviewItem(
            id: id,
            kind: classifyText(normalized),
            title: makeTitle(from: normalized),
            preview: makePreview(from: normalized),
            content: normalized,
            capturedAt: capturedAt
        )
    }
}

private func classifyText(_ content: String) -> ContextAssetKind {
    if let scheme = URL(string: content)?.scheme?.lowercased(),
        ["http", "https", "file"].contains(scheme) {
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

private func makeTitle(from content: String) -> String {
    let firstLine = content
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init) ?? "Captured text"
    return truncated(firstLine, limit: 48)
}

private func makePreview(from content: String) -> String {
    truncated(content.replacingOccurrences(of: "\n", with: " "), limit: 160)
}

private func truncated(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    let end = value.index(value.startIndex, offsetBy: limit)
    return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}
