import XCTest
@testable import OnPaperCore

final class CapturePreviewTests: XCTestCase {
    func testStartsWithPlaceholderAndNoCapturedItem() {
        let state = InMemoryCapturePreviewState()

        XCTAssertEqual(state.snapshot.placeholder, "No capture yet")
        XCTAssertNil(state.snapshot.latestItem)
    }

    func testCapturesTextInMemoryAndDerivesPreviewFromFullContent() {
        var state = InMemoryCapturePreviewState()
        let fullContent = """
        Failing login test
        expected button to be enabled but it was disabled after submit
        """

        state.captureText(
            fullContent,
            capturedAt: Date(timeIntervalSince1970: 1_783_245_000),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        let item = state.snapshot.latestItem
        XCTAssertEqual(item?.kind, .text)
        XCTAssertEqual(item?.title, "Failing login test")
        XCTAssertEqual(
            item?.content,
            "Failing login test\nexpected button to be enabled but it was disabled after submit"
        )
        XCTAssertEqual(
            item?.preview,
            "Failing login test expected button to be enabled but it was disabled after submit"
        )
    }

    func testClassifiesUrlCodeAndLogTextForPreview() {
        var state = InMemoryCapturePreviewState()

        state.captureText("https://example.com/issue/1")
        XCTAssertEqual(state.snapshot.latestItem?.kind, .url)

        state.captureText("struct LoginView {}")
        XCTAssertEqual(state.snapshot.latestItem?.kind, .code)

        state.captureText("ERROR: login test failed")
        XCTAssertEqual(state.snapshot.latestItem?.kind, .log)
    }

    func testEmptyCaptureDoesNotReplaceExistingPreview() {
        var state = InMemoryCapturePreviewState()
        state.captureText("keep me")
        let existing = state.snapshot.latestItem

        state.captureText("   \n   ")

        XCTAssertEqual(state.snapshot.latestItem, existing)
    }
}
