import XCTest
@testable import OnPaperCore

final class ContextAssetStoreTests: XCTestCase {
    func testFileBackedStorePersistsFullContentAndSourceMetadataAcrossInstances() async throws {
        let fileURL = try makeTemporaryStoreURL()
        let capturedAt = Date(timeIntervalSince1970: 1_783_250_000)
        let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sourceApp = SourceAppMetadata(name: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let draft = ContextAssetDraft.textLike(
            content: "ERROR: login test failed with a long diagnostic payload",
            capturedAt: capturedAt,
            sourceApp: sourceApp
        )

        let store = FileBackedContextAssetStore(fileURL: fileURL)
        let asset = try await store.create(XCTUnwrap(draft), id: id)
        let reloadedStore = FileBackedContextAssetStore(fileURL: fileURL)

        let recent = try await reloadedStore.recent(limit: 10)

        XCTAssertEqual(recent, [asset])
        XCTAssertEqual(asset.id, id)
        XCTAssertEqual(asset.kind, .log)
        XCTAssertEqual(asset.title, "ERROR: login test failed with a long diagnostic...")
        XCTAssertEqual(asset.content, "ERROR: login test failed with a long diagnostic payload")
        XCTAssertEqual(asset.capturedAt, capturedAt)
        XCTAssertEqual(asset.sourceApp, sourceApp)
    }

    func testExplicitClipboardCapturePersistsOnlyWhenCalled() async throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = FileBackedContextAssetStore(fileURL: fileURL)
        let reader = FakeClipboardTextReader(text: "https://example.com/issues/3")
        let sourceProvider = FakeSourceAppMetadataProvider(
            metadata: SourceAppMetadata(name: "Safari", bundleIdentifier: "com.apple.Safari")
        )
        let service = TextClipboardCaptureService(
            reader: reader,
            sourceProvider: sourceProvider,
            store: store,
            now: { Date(timeIntervalSince1970: 1_783_250_100) },
            makeID: { UUID(uuidString: "10000000-0000-0000-0000-000000000002")! }
        )

        let beforeCapture = try await store.recent(limit: 10)
        XCTAssertEqual(beforeCapture, [])

        let captured = try await service.captureCurrentClipboard()
        let asset = try XCTUnwrap(captured)

        XCTAssertEqual(asset.kind, .url)
        XCTAssertEqual(asset.content, "https://example.com/issues/3")
        XCTAssertEqual(asset.metadata["host"], "example.com")
        let afterCapture = try await store.recent(limit: 10)
        XCTAssertEqual(afterCapture, [asset])
    }

    func testOrdinaryClipboardChangeIsNotPersistedWithoutExplicitCapture() async throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = FileBackedContextAssetStore(fileURL: fileURL)
        let reader = FakeClipboardTextReader(text: "struct LoginView {}")
        _ = TextClipboardCaptureService(
            reader: reader,
            sourceProvider: EmptySourceAppMetadataProvider(),
            store: store
        )

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent, [])
    }

    func testCanonicalRendererUsesFullContentNotPreview() throws {
        let longContent = String(repeating: "full-content-", count: 30)
        let draft = try XCTUnwrap(ContextAssetDraft.textLike(content: longContent))
        let asset = ContextAsset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            kind: draft.kind,
            title: draft.title,
            preview: draft.preview,
            content: draft.content,
            capturedAt: draft.capturedAt
        )

        XCTAssertNotEqual(asset.preview, asset.content)
        XCTAssertEqual(ContextAssetCanonicalTextRenderer().render(asset), longContent)
    }

    func testTextLikeDraftClassifiesSupportedKinds() throws {
        XCTAssertEqual(try XCTUnwrap(ContextAssetDraft.textLike(content: "plain note")).kind, .text)
        XCTAssertEqual(try XCTUnwrap(ContextAssetDraft.textLike(content: "https://example.com")).kind, .url)
        XCTAssertEqual(try XCTUnwrap(ContextAssetDraft.textLike(content: "func run() {}")).kind, .code)
        XCTAssertEqual(try XCTUnwrap(ContextAssetDraft.textLike(content: "Exception: failed test")).kind, .log)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("onpaper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ContextAssets.json")
    }
}

private struct FakeClipboardTextReader: ClipboardTextReading {
    var text: String?

    func currentString() -> String? {
        text
    }
}

private struct FakeSourceAppMetadataProvider: SourceAppMetadataProviding {
    var metadata: SourceAppMetadata?

    func currentSourceAppMetadata() -> SourceAppMetadata? {
        metadata
    }
}
