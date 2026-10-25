@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    func testProgressSelectionAndImage() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {
          "targets": [{"amount": 100, "title": "Next & <goal>"}, {"amount": 50, "title": "First"}],
          "statuses": [{"amount": 50, "description": "Reached"}, {"amount": 0, "description": "Starting"}]
        }
        """.utf8))
        let dashboard = try ProgressDashboard(amount: 75.5, config: config)
        XCTAssertEqual(dashboard.previous?.amount, 50)
        XCTAssertEqual(dashboard.next?.amount, 100)
        XCTAssertEqual(dashboard.status?.description, "Reached")
        XCTAssertEqual(dashboard.fraction, 0.51, accuracy: 0.0001)
        let image = dashboard.svg()
        XCTAssertTrue(image.contains("$76 / month"))
        XCTAssertTrue(image.contains("Next &amp; &lt;goal&gt;"))
        XCTAssertTrue(image.contains("✓ First"))
        XCTAssertTrue(image.contains("○ Next &amp; &lt;goal&gt;"))

        let boundary = try ProgressDashboard(amount: 50, config: config)
        XCTAssertEqual(boundary.status?.description, "Starting")
        XCTAssertEqual(boundary.fraction, 0)
        let complete = try ProgressDashboard(amount: 100, config: config)
        XCTAssertNil(complete.next)
        XCTAssertEqual(complete.fraction, 1)
        XCTAssertTrue(complete.svg().contains("ALL TARGETS REACHED"))
    }

    func testInvalidTargetsAreRejected() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {"targets":[{"amount":0,"title":"Invalid"}],"statuses":[]}
        """.utf8))
        XCTAssertThrowsError(try ProgressDashboard(amount: 20, config: config))
    }

    func testSuccessfulGenerationIsThrottledButFailureIsRetryable() async {
        let gate = ProgressGenerationGate()
        let start = Date(timeIntervalSince1970: 1000)
        let first = await gate.begin(at: start)
        let concurrent = await gate.begin(at: start)
        XCTAssertTrue(first)
        XCTAssertFalse(concurrent)
        await gate.finish(succeeded: false, at: start)
        let retry = await gate.begin(at: start)
        XCTAssertTrue(retry)
        await gate.finish(succeeded: true, at: start)
        let tooSoon = await gate.begin(at: start.addingTimeInterval(59))
        let due = await gate.begin(at: start.addingTimeInterval(60))
        XCTAssertFalse(tooSoon)
        XCTAssertTrue(due)
    }

    func testImageRendersAndReplacesAtomically() throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/rsvg-convert") else {
            throw XCTSkip("librsvg2-bin is installed in the production image")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {"targets":[{"amount":50,"title":"First"}],"statuses":[]}
        """.utf8))
        let image = try ProgressDashboard(amount: 25, config: config).svg()
        try ProgressDashboardService.render(image, to: directory.path)
        try ProgressDashboardService.render(image, to: directory.path)
        let bytes = try Data(contentsOf: directory.appendingPathComponent("progressDashboard.png"))
        XCTAssertEqual(Array(bytes.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }
}
