@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    static let fixtureJSON = """
    {
      "targets": [
        {"amount": 50, "title": "Goal title", "title_achieved": "Achieved title"},
        {"amount": 100, "title": "Next goal title", "title_achieved": "Next achieved title"}
      ],
      "statuses": [{"amount": 0, "description": "Starting status"}, {"amount": 50, "description": "Halfway status"}]
    }
    """

    private func loadConfig(_ json: String) throws -> ProgressConfig {
        try JSONDecoder().decode(ProgressConfig.self, from: Data(json.utf8))
    }

    func testGoalCaptionUsesTitleUntilAchievedThenTitleAchieved() throws {
        let config = try loadConfig(Self.fixtureJSON)
        let before = try ProgressDashboard(amount: 49, config: config).svg()
        XCTAssertTrue(before.contains(">Goal title</text>"))
        XCTAssertFalse(before.contains("Achieved title"))

        let atGoal = try ProgressDashboard(amount: 50, config: config).svg()
        XCTAssertTrue(atGoal.contains(">Achieved title</text>"))
        XCTAssertTrue(atGoal.contains(">Next goal title</text>"))
        XCTAssertFalse(atGoal.contains(">Goal title</text>"))

        let complete = try ProgressDashboard(amount: 100, config: config).svg()
        XCTAssertTrue(complete.contains(">Next achieved title</text>"))
        XCTAssertFalse(complete.contains("Next goal title"))
    }

    func testTargetRequiresNonEmptyTitleAchieved() throws {
        XCTAssertThrowsError(try loadConfig(#"{"targets":[{"amount":50,"title":"T"}],"statuses":[]}"#))
        let empty = try loadConfig(#"{"targets":[{"amount":50,"title":"T","title_achieved":""}],"statuses":[]}"#)
        XCTAssertThrowsError(try ProgressDashboard(amount: 20, config: empty))
    }

    func testProgressSelectionAndImage() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {
          "targets": [{"amount": 100, "title": "Next & <goal>", "title_achieved": "Next achieved"}, {"amount": 50, "title": "First", "title_achieved": "First achieved"}],
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
        let config = try loadConfig(Self.fixtureJSON)
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
        XCTAssertTrue(first.contains(">Goal title</text>"))
        XCTAssertTrue(first.contains("Starting status"))
        let exceeded = try ProgressDashboard(amount: 600, config: config).svg()
        XCTAssertTrue(exceeded.contains(">Next achieved title</text>"))
        XCTAssertFalse(exceeded.contains("Next goal title"))
    }

    func testBarUsesSolidColorInterpolatedUntilFirstGoal() throws {
        let config = try loadConfig(Self.fixtureJSON)
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
          {"amount":50,"title":"Server expenses are fully covered","title_achieved":"Server costs are fully covered"},
          {"amount":100,"title":"Some room for bugfixes, minor improvements and feature requests","title_achieved":"Room for improvements"}
        ],"statuses":[]}
        """.utf8))
        let image = try ProgressDashboard(amount: 75, config: config).svg()
        XCTAssertTrue(image.contains("x=\"175\" y=\"234\" text-anchor=\"start\""))
        XCTAssertTrue(image.contains("Server costs are fully</text>"))
        XCTAssertTrue(image.contains(">covered</text>"))
        XCTAssertFalse(image.contains("Server expenses are fully covered"))
        XCTAssertTrue(image.contains("x=\"1025\" y=\"234\" text-anchor=\"end\""))
        XCTAssertTrue(image.contains("x=\"1025\" y=\"255\" text-anchor=\"end\""))
        XCTAssertTrue(image.contains("minor improvements and"))
        XCTAssertFalse(image.contains("TARGETS"))
    }

    func testInvalidTargetsAreRejected() throws {
        let config = try JSONDecoder().decode(ProgressConfig.self, from: Data("""
        {"targets":[{"amount":0,"title":"Invalid","title_achieved":"Invalid"}],"statuses":[]}
        """.utf8))
        XCTAssertThrowsError(try ProgressDashboard(amount: 20, config: config))
    }

    func testMembersSumActivePatrons() throws {
        let members = try JSONDecoder().decode(PatreonMembers.self, from: Data("""
        {"data":[{"attributes":{"patron_status":"active_patron","will_pay_amount_cents":3500,"last_charge_status":"Paid"}},
        {"attributes":{"patron_status":"former_patron","will_pay_amount_cents":0}},
        {"attributes":{"patron_status":"active_patron","will_pay_amount_cents":900,"last_charge_status":"Declined"}},
        {"attributes":{"patron_status":"active_patron","will_pay_amount_cents":500,"last_charge_status":null}}],
        "meta":{"pagination":{"cursors":{"next":"abc"}}}}
        """.utf8))
        XCTAssertEqual(members.activeCents, 4000)
        XCTAssertEqual(members.nextCursor, "abc")
        XCTAssertTrue(ProgressDashboardService.membersURI(campaignID: "1", cursor: nil).string.contains("will_pay_amount_cents"))
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
        let config = try loadConfig(#"{"targets":[{"amount":50,"title":"First","title_achieved":"First achieved"}],"statuses":[]}"#)
        let image = try ProgressDashboard(amount: 25, config: config).svg()
        try ProgressDashboardService.render(image, to: directory.path)
        try ProgressDashboardService.render(image, to: directory.path)
        let bytes = try Data(contentsOf: directory.appendingPathComponent("progressDashboard.png"))
        XCTAssertEqual(Array(bytes.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }
}
