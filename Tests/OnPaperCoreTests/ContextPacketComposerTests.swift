import XCTest
@testable import OnPaperCore

final class ContextPacketComposerTests: XCTestCase {
    func testCreatesPacketWithGoalIntentOrderedAssetIDsAndTimestamps() async throws {
        let packetStoreURL = try makeTemporaryStoreURL(named: "ContextPackets.json")
        let packetStore = FileBackedContextPacketStore(fileURL: packetStoreURL)
        let id1 = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let id2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let createdAt = Date(timeIntervalSince1970: 1_783_260_000)

        let packet = try await packetStore.create(
            ContextPacketDraft(
                goal: "  Fix the login regression  ",
                intent: .debug,
                assetIDs: [id2, id1]
            ),
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
            now: createdAt
        )

        let reloadedStore = FileBackedContextPacketStore(fileURL: packetStoreURL)
        let reloaded = try await reloadedStore.resolve(packet.id)

        XCTAssertEqual(packet.goal, "Fix the login regression")
        XCTAssertEqual(packet.intent, .debug)
        XCTAssertEqual(packet.assetIDs, [id2, id1])
        XCTAssertEqual(packet.createdAt, createdAt)
        XCTAssertEqual(packet.updatedAt, createdAt)
        XCTAssertEqual(reloaded, packet)
    }

    func testComposerRendersAssetsInSelectedOrderFromFullContentNotPreview() async throws {
        let assetStore = FileBackedContextAssetStore(fileURL: try makeTemporaryStoreURL(named: "ContextAssets.json"))
        let packetStore = FileBackedContextPacketStore(fileURL: try makeTemporaryStoreURL(named: "ContextPackets.json"))
        let logID = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        let codeID = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!
        let capturedAt = Date(timeIntervalSince1970: 1_783_260_100)
        _ = try await assetStore.create(
            ContextAssetDraft(
                kind: .log,
                title: "Short log title",
                preview: "preview-log-only",
                content: "FULL LOG CONTENT\nline two",
                capturedAt: capturedAt,
                sourceApp: SourceAppMetadata(name: "Terminal")
            ),
            id: logID
        )
        _ = try await assetStore.create(
            ContextAssetDraft(
                kind: .code,
                title: "Short code title",
                preview: "preview-code-only",
                content: "func runLoginTest() {}",
                capturedAt: capturedAt,
                sourceApp: SourceAppMetadata(name: "Xcode")
            ),
            id: codeID
        )
        let composer = ContextPacketComposer(
            assetStore: assetStore,
            packetStore: packetStore,
            now: { Date(timeIntervalSince1970: 1_783_260_200) },
            makeID: { UUID(uuidString: "20000000-0000-0000-0000-000000000006")! }
        )

        let packet = try await composer.createDraft(
            goal: "Fix ordering",
            intent: .implement,
            assetIDs: [codeID, logID]
        )
        let preview = try await composer.render(packet).text

        XCTAssertLessThan(
            try XCTUnwrap(preview.range(of: "1. [code] Short code title")?.lowerBound),
            try XCTUnwrap(preview.range(of: "2. [log] Short log title")?.lowerBound)
        )
        XCTAssertTrue(preview.contains("func runLoginTest() {}"))
        XCTAssertTrue(preview.contains("FULL LOG CONTENT\n   line two"))
        XCTAssertFalse(preview.contains("preview-code-only"))
        XCTAssertFalse(preview.contains("preview-log-only"))
    }

    func testRenderingIsDeterministicForSamePacketAndAssets() async throws {
        let assetStore = FileBackedContextAssetStore(fileURL: try makeTemporaryStoreURL(named: "ContextAssets.json"))
        let packetStore = FileBackedContextPacketStore(fileURL: try makeTemporaryStoreURL(named: "ContextPackets.json"))
        let assetID = UUID(uuidString: "20000000-0000-0000-0000-000000000007")!
        _ = try await assetStore.create(
            ContextAssetDraft(
                kind: .text,
                title: "Requirement",
                preview: "short preview",
                content: "Use full requirement body",
                capturedAt: Date(timeIntervalSince1970: 1_783_260_300)
            ),
            id: assetID
        )
        let composer = ContextPacketComposer(
            assetStore: assetStore,
            packetStore: packetStore,
            now: { Date(timeIntervalSince1970: 1_783_260_400) },
            makeID: { UUID(uuidString: "20000000-0000-0000-0000-000000000008")! }
        )

        let packet = try await composer.createDraft(goal: "Review this", intent: .review, assetIDs: [assetID])
        let first = try await composer.render(packet)
        let second = try await composer.render(packet)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.text, second.text)
    }

    func testComposerFailsWhenSelectedAssetIsMissing() async throws {
        let assetStore = FileBackedContextAssetStore(fileURL: try makeTemporaryStoreURL(named: "ContextAssets.json"))
        let packetStore = FileBackedContextPacketStore(fileURL: try makeTemporaryStoreURL(named: "ContextPackets.json"))
        let missingID = UUID(uuidString: "20000000-0000-0000-0000-000000000009")!
        let composer = ContextPacketComposer(assetStore: assetStore, packetStore: packetStore)

        do {
            _ = try await composer.createDraft(goal: "Explain missing context", intent: .explain, assetIDs: [missingID])
            XCTFail("Expected missing asset error")
        } catch ContextPacketComposerError.missingAsset(missingID) {
        }
        let latestPacket = try await packetStore.latest()
        XCTAssertNil(latestPacket)
    }

    private func makeTemporaryStoreURL(named fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("onpaper-packet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

}
