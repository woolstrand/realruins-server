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
        XCTAssertEqual(dashboard.fraction, 30.5 / 60, accuracy: 0.0001)
        let image = dashboard.svg()
        XCTAssertTrue(image.contains("width=\"1200\" height=\"416\""))
        XCTAssertTrue(image.contains("$76 <tspan"))
        XCTAssertTrue(image.contains(">/ month</tspan>"))
        XCTAssertTrue(image.contains("Next &amp; &lt;goal&gt;"))
        XCTAssertTrue(image.contains("x=\"90\" y=\"137\" width=\"518\" height=\"28\""))
        XCTAssertTrue(image.contains("<line x1=\"175\" y1=\"124\""))
        XCTAssertTrue(image.contains("<line x1=\"1025\" y1=\"124\""))
        XCTAssertFalse(image.contains("CURRENT STATUS"))
        XCTAssertFalse(image.contains("MONTHLY PATREON SUPPORT"))
        XCTAssertTrue(image.contains("Amounts are approximate, after subtracting processing fees and taxes. Refreshes daily."))

        let before = try ProgressDashboard(amount: 25, config: config).svg()
        XCTAssertEqual(before.components(separatedBy: "<line x1=").count - 1, 1)
        XCTAssertTrue(before.contains("x=\"90\" y=\"137\" width=\"463\" height=\"28\""))
        XCTAssertTrue(before.contains("<line x1=\"1017\" y1=\"124\""))
        XCTAssertFalse(before.contains("$100</text>"))
        let boundary = try ProgressDashboard(amount: 50, config: config)
        XCTAssertEqual(boundary.status?.description, "Starting")
        XCTAssertEqual(boundary.fraction, 5 / 60, accuracy: 0.0001)
        XCTAssertTrue(boundary.svg().contains("x=\"90\" y=\"137\" width=\"85\" height=\"28\""))
        XCTAssertTrue(boundary.svg().contains("<line x1=\"175\" y1=\"124\""))
        let complete = try ProgressDashboard(amount: 100, config: config)
        XCTAssertNil(complete.next)
        XCTAssertEqual(complete.fraction, 1)
        XCTAssertEqual(complete.svg().components(separatedBy: "<line x1=").count - 1, 1)
        XCTAssertTrue(complete.svg().contains("<line x1=\"1110\" y1=\"124\""))
        let exceeded = try ProgressDashboard(amount: 200, config: config).svg()
        XCTAssertTrue(exceeded.contains("width=\"1020\" height=\"28\""))
        XCTAssertTrue(exceeded.contains("<line x1=\"600\" y1=\"124\""))
        XCTAssertTrue(try ProgressDashboard(amount: 600, config: config).svg().contains("<line x1=\"260\" y1=\"124\""))
    }

    func testGaugeUsesSameAxisForFillAndGoalMarkers() throws {
        let config = try JSONDecoder().decode(
            ProgressConfig.self,
            from: Data(contentsOf: URL(fileURLWithPath: "Resources/progress-targets.json"))
        )
        for (amount, fillWidth, markers) in [
            (10, 185, [1017]), (40, 741, [1017]), (49, 908, [1017]),
            (50, 85, [175, 1025]), (51, 102, [175, 1025]),
            (90, 765, [175, 1025]), (110, 1020, [1017]), (600, 1020, [260])
        ] {
            let image = try ProgressDashboard(amount: Double(amount), config: config).svg()
            XCTAssertTrue(image.contains("x=\"90\" y=\"137\" width=\"\(fillWidth)\" height=\"28\""), "\(amount)")
            XCTAssertEqual(image.components(separatedBy: "<line x1=").count - 1, markers.count, "\(amount)")
            for marker in markers {
                XCTAssertTrue(image.contains("<line x1=\"\(marker)\" y1=\"124\""), "\(amount)")
            }
        }
        let first = try ProgressDashboard(amount: 10, config: config).svg()
        XCTAssertTrue(first.contains("Server expenses are fully covered</text>"))
        XCTAssertTrue(first.contains("for too long..."))
        let exceeded = try ProgressDashboard(amount: 600, config: config).svg()
        XCTAssertTrue(exceeded.contains("Some room for bugfixes, minor improvements and feature requests</text>"))
    }

    func testBarUsesSolidColorInterpolatedUntilFirstGoal() throws {
        let config = try JSONDecoder().decode(
            ProgressConfig.self,
            from: Data(contentsOf: URL(fileURLWithPath: "Resources/progress-targets.json"))
        )
        for (amount, color) in [
            (0, "#E95C5C"), (3, "#E95C5C"), (5, "#E95C5C"),
            (10, "#EA7163"), (35, "#F1D887"), (45, "#89D798"),
            (50, "#55D6A0"), (60, "#55D6A0"), (600, "#55D6A0")
        ] {
            let dashboard = try ProgressDashboard(amount: Double(amount), config: config)
            XCTAssertEqual(dashboard.barColor, color, "\(amount)")
            let image = dashboard.svg()
            XCTAssertTrue(image.contains("y=\"137\" width=\"\(Int(1020 * dashboard.fraction))\" height=\"28\" rx=\"14\" fill=\"\(color)\""), "\(amount)")
            XCTAssertEqual(image.components(separatedBy: "fill=\"\(color)\"").count - 1, 1, "\(amount)")
        }
    }

    func testLongGoalCaptionsWrapNextToMarkers() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {"targets":[
          {"amount":50,"title":"Server expenses are fully covered"},
          {"amount":100,"title":"Some room for bugfixes, minor improvements and feature requests"}
        ],"statuses":[]}
        """.utf8))
        let image = try ProgressDashboard(amount: 75, config: config).svg()
        XCTAssertTrue(image.contains("x=\"175\" y=\"234\" text-anchor=\"start\""))
        XCTAssertTrue(image.contains("x=\"1025\" y=\"234\" text-anchor=\"end\""))
        XCTAssertTrue(image.contains("x=\"1025\" y=\"255\" text-anchor=\"end\""))
        XCTAssertTrue(image.contains("minor improvements and"))
        XCTAssertFalse(image.contains("TARGETS"))
    }

    func testInvalidTargetsAreRejected() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {"targets":[{"amount":0,"title":"Invalid"}],"statuses":[]}
        """.utf8))
        XCTAssertThrowsError(try ProgressDashboard(amount: 20, config: config))
    }

    func testCampaignsDecodePledgeSum() throws {
        let campaigns = try JSONDecoder().decode(PatreonCampaigns.self, from: Data("""
        {"data":[{"id":"1","attributes":{"pledge_sum":3500}}]}
        """.utf8))
        XCTAssertEqual(campaigns.data[0].attributes?.pledge_sum, 3500)
        XCTAssertTrue(ProgressDashboardService.campaignsURI.string.contains("pledge_sum"))
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
        if let sampleDirectory = ProcessInfo.processInfo.environment["PROGRESS_SAMPLE_DIRECTORY"] {
            let sampleConfig = try JSONDecoder().decode(
                ProgressConfig.self,
                from: Data(contentsOf: URL(fileURLWithPath: "Resources/progress-targets.json"))
            )
            for amount in [3, 10, 35, 45, 60] {
                let sample = try ProgressDashboard(amount: Double(amount), config: sampleConfig).svg()
                try ProgressDashboardService.render(sample, to: directory.path)
                try Data(contentsOf: directory.appendingPathComponent("progressDashboard.png")).write(
                    to: URL(fileURLWithPath: sampleDirectory).appendingPathComponent("progressDashboard-\(amount).png"),
                    options: .atomic
                )
            }
        }
    }
}
