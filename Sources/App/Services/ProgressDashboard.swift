import Foundation
import Vapor
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

struct ProgressConfig: Decodable {
    struct Target: Decodable {
        let amount: Double
        let title: String
    }

    struct Status: Decodable {
        let amount: Double
        let description: String
    }

    let targets: [Target]
    let statuses: [Status]

    func validate() throws {
        guard !targets.isEmpty,
              targets.allSatisfy({ $0.amount > 0 && $0.amount.isFinite && !$0.title.isEmpty }),
              statuses.allSatisfy({ $0.amount >= 0 && $0.amount.isFinite && !$0.description.isEmpty }),
              Set(targets.map(\.amount)).count == targets.count else {
            throw ProgressError.invalidConfiguration
        }
    }
}

enum ProgressError: Error {
    case invalidConfiguration
    case invalidPledge
    case renderingFailed
}

struct ProgressDashboard {
    let amount: Double
    let previous: ProgressConfig.Target?
    let next: ProgressConfig.Target?
    let status: ProgressConfig.Status?
    let targets: [ProgressConfig.Target]

    init(amount: Double, config: ProgressConfig) throws {
        try config.validate()
        guard amount.isFinite, amount >= 0 else { throw ProgressError.invalidPledge }
        self.amount = amount
        targets = config.targets.sorted { $0.amount < $1.amount }
        previous = targets.last { $0.amount <= amount }
        next = targets.first { $0.amount > amount }
        status = config.statuses.filter { $0.amount < amount }.max { $0.amount < $1.amount }
    }

    private var axis: (start: Double, end: Double) {
        guard let next = next else { return (0, amount) }
        let lower = previous?.amount ?? 0
        let gap = next.amount - lower
        return (previous == nil ? 0 : lower - gap * 0.1, next.amount + gap * 0.1)
    }

    var fraction: Double {
        let axis = axis
        return min(1, max(0, (amount - axis.start) / (axis.end - axis.start)))
    }

    var barColor: String {
        let progress = amount / targets[0].amount
        if progress <= 0.1 { return "#E95C5C" }
        if progress < 0.7 {
            return blend((233, 92, 92), (241, 216, 135), fraction: (progress - 0.1) / 0.6)
        }
        if progress < 1 {
            return blend((241, 216, 135), (85, 214, 160), fraction: (progress - 0.7) / 0.3)
        }
        return "#55D6A0"
    }

    func svg() -> String {
        let barX = 90
        let barWidth = 1020
        let axis = axis
        func position(_ value: Double) -> Int {
            barX + Int(Double(barWidth) * ((value - axis.start) / (axis.end - axis.start)))
        }
        let statusLines = captionLines(status?.description ?? "No current status", limit: 90, maxLines: 2)
        var body = """
        <rect x="24" y="20" width="1152" height="376" rx="20" fill="#1b2d40"/>
        <text x="90" y="91" fill="#ffffff" font-size="48" font-weight="300">\(dollars(amount)) <tspan fill="#a9c4d9" font-size="26">/ month</tspan></text>
        <rect x="\(barX)" y="137" width="\(barWidth)" height="28" rx="14" fill="#40546a"/>
        <rect x="\(barX)" y="137" width="\(Int(Double(barWidth) * fraction))" height="28" rx="14" fill="\(barColor)"/>
        """
        if let previous = previous {
            let markerX = position(previous.amount)
            body += goalCaption(previous, x: markerX, anchor: markerX > barX + barWidth / 2 ? "end" : "start", wide: next == nil)
        }
        if let next = next {
            body += goalCaption(next, x: position(next.amount), anchor: "end", wide: previous == nil)
        }
        for (index, line) in statusLines.enumerated() {
            body += """
            <text x="90" y="\(313 + index * 23)" fill="#ffffff" font-size="20" font-style="italic">\(escape(line))</text>
            """
        }
        body += """
        <text x="90" y="363" fill="#a9c4d9" font-size="14">Amounts are approximate, after subtracting processing fees and taxes. Refreshes daily.</text>
        """
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="416" viewBox="0 0 1200 416" font-family="DejaVu Sans, sans-serif" font-weight="300">
        \(body)
        </svg>
        """
    }

    private func goalCaption(_ target: ProgressConfig.Target, x: Int, anchor: String, wide: Bool) -> String {
        var result = """
        <line x1="\(x)" y1="124" x2="\(x)" y2="180" stroke="#ffffff" stroke-width="3"/>
        <text x="\(x)" y="210" text-anchor="\(anchor)" fill="#ffffff" font-size="21">\(dollars(target.amount))</text>
        """
        for (index, line) in captionLines(target.title, limit: wide ? 64 : 27, maxLines: 3).enumerated() {
            result += """
            <text x="\(x)" y="\(234 + index * 21)" text-anchor="\(anchor)" fill="#c6d4df" font-size="17">\(escape(line))</text>
            """
        }
        return result
    }
}

private func blend(_ start: (Int, Int, Int), _ end: (Int, Int, Int), fraction: Double) -> String {
    func channel(_ from: Int, _ to: Int) -> Int {
        Int((Double(from) + Double(to - from) * fraction).rounded())
    }
    return String(format: "#%02X%02X%02X",
                  channel(start.0, end.0), channel(start.1, end.1), channel(start.2, end.2))
}

private func dollars(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    formatter.locale = Locale(identifier: "en_US")
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
}

private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private func captionLines(_ value: String, limit: Int, maxLines: Int) -> [String] {
    let lines = wrapped(value, limit: limit)
    guard lines.count > maxLines else { return lines }
    var result = Array(lines.prefix(maxLines))
    result[maxLines - 1] = String(result[maxLines - 1].prefix(limit - 1)) + "…"
    return result
}

private func wrapped(_ value: String, limit: Int) -> [String] {
    var lines: [String] = []
    var line = ""
    for word in value.split(separator: " ") {
        var remainder = String(word)
        while !remainder.isEmpty {
            let available = limit - line.count - (line.isEmpty ? 0 : 1)
            if available == 0 {
                lines.append(line)
                line = ""
                continue
            }
            if remainder.count <= available {
                line += (line.isEmpty ? "" : " ") + remainder
                break
            }
            if !line.isEmpty {
                lines.append(line)
                line = ""
                continue
            }
            lines.append(String(remainder.prefix(limit)))
            remainder = String(remainder.dropFirst(limit))
        }
    }
    lines.append(line)
    return lines
}

struct PatreonCampaigns: Decodable {
    struct Campaign: Decodable {
        let id: String
    }
    let data: [Campaign]
}

struct PatreonMembers: Decodable {
    struct Member: Decodable {
        struct Attributes: Decodable {
            let patron_status: String?
            let currently_entitled_amount_cents: Int?
        }
        let attributes: Attributes?
    }
    struct Meta: Decodable {
        struct Pagination: Decodable {
            struct Cursors: Decodable { let next: String? }
            let cursors: Cursors?
        }
        let pagination: Pagination?
    }
    let data: [Member]
    let meta: Meta?

    var nextCursor: String? { meta?.pagination?.cursors?.next }

    /// Monthly cents pledged by currently active patrons on this page.
    var activeCents: Int {
        data.reduce(0) { sum, member in
            guard member.attributes?.patron_status == "active_patron" else { return sum }
            return sum + max(member.attributes?.currently_entitled_amount_cents ?? 0, 0)
        }
    }
}

struct PatreonPublicCampaign: Decodable {
    struct Campaign: Decodable {
        struct Attributes: Decodable {
            let pledge_sum: Int?
        }

        let attributes: Attributes
    }

    let data: Campaign
}

private protocol PatreonFundingSource {
    var name: String { get }

    func fundingCents(for req: Request) async throws -> Int
}

private struct PatreonMemberFundingSource: PatreonFundingSource {
    let name = "Patreon member API"

    func fundingCents(for req: Request) async throws -> Int {
        guard let token = Environment.get("PATREON_ACCESS_TOKEN"), !token.isEmpty else {
            throw Abort(.internalServerError, reason: "PATREON_ACCESS_TOKEN is not configured")
        }

        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        let campaigns = try JSONDecoder().decode(
            PatreonCampaigns.self,
            from: try await ProgressDashboardService.patreonData(
                ProgressDashboardService.campaignsURI,
                req: req,
                headers: headers
            )
        )
        let campaignID = Environment.get("PATREON_CAMPAIGN_ID")
        let selected = campaignID == nil ? campaigns.data : campaigns.data.filter { $0.id == campaignID }
        guard selected.count == 1 else {
            throw Abort(.badGateway, reason: "Expected one Patreon campaign; configure PATREON_CAMPAIGN_ID if there are multiple")
        }
        let id = selected[0].id
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
            throw Abort(.badGateway, reason: "Patreon returned an invalid campaign ID")
        }

        var pledgeSum = 0
        var cursor: String?
        repeat {
            let page = try JSONDecoder().decode(
                PatreonMembers.self,
                from: try await ProgressDashboardService.patreonData(
                    ProgressDashboardService.membersURI(campaignID: id, cursor: cursor),
                    req: req,
                    headers: headers
                )
            )
            pledgeSum += page.activeCents
            cursor = page.nextCursor
        } while cursor != nil
        return pledgeSum
    }
}

private struct PatreonPublicCampaignFundingSource: PatreonFundingSource {
    let name = "Patreon public campaign API"

    func fundingCents(for req: Request) async throws -> Int {
        let campaign = try JSONDecoder().decode(
            PatreonPublicCampaign.self,
            from: try await ProgressDashboardService.patreonData(
                ProgressDashboardService.publicCampaignURI,
                req: req
            )
        )
        guard let pledgeSum = campaign.data.attributes.pledge_sum, pledgeSum >= 0 else {
            throw Abort(.badGateway, reason: "Patreon public campaign API returned an invalid pledge sum")
        }
        return pledgeSum
    }
}

/// Share of Patreon's monthly income assumed to reach the creator after fees and losses.
let patreonPayoutFactor = 0.85

actor ProgressGenerationGate {
    private var lastGenerated: Date?
    private var generating = false

    init(lastGenerated: Date? = nil) {
        self.lastGenerated = lastGenerated
    }

    func begin(at date: Date = Date()) -> Bool {
        if generating || (lastGenerated.map { date.timeIntervalSince($0) < 60 } ?? false) {
            return false
        }
        generating = true
        return true
    }

    func finish(succeeded: Bool, at date: Date = Date()) {
        if succeeded { lastGenerated = date }
        generating = false
    }
}

final class ProgressDashboardService {
    private let gate: ProgressGenerationGate
    private let publicDirectory: String
    private let resourcesDirectory: String

    init(publicDirectory: String, resourcesDirectory: String) {
        self.publicDirectory = publicDirectory
        self.resourcesDirectory = resourcesDirectory
        let image = URL(fileURLWithPath: publicDirectory).appendingPathComponent("progressDashboard.png")
        let modified = try? image.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        gate = ProgressGenerationGate(lastGenerated: modified)
    }

    func generate(_ req: Request) async -> Response {
        guard await gate.begin() else { return response("throttled") }
        do {
            let config = try JSONDecoder().decode(
                ProgressConfig.self,
                from: Data(contentsOf: URL(fileURLWithPath: resourcesDirectory).appendingPathComponent("progress-targets.json"))
            )
            try config.validate()
            let fundingCents = try await Self.fundingCents(for: req)
            let dashboard = try ProgressDashboard(amount: Double(fundingCents) / 100 * patreonPayoutFactor, config: config)
            let svg = dashboard.svg()
            try await Task.detached {
                try Self.render(svg, to: self.publicDirectory)
            }.value
            await gate.finish(succeeded: true)
            return response("generated")
        } catch {
            await gate.finish(succeeded: false)
            req.logger.error("Progress dashboard generation failed: \(error)")
            return response("error", status: .internalServerError)
        }
    }

    static let campaignsURI = URI(string: "https://www.patreon.com/api/oauth2/v2/campaigns")
    static let publicCampaignURI = URI(string: "https://www.patreon.com/api/campaigns/2186817?fields%5Bcampaign%5D=creation_count%2Cmember_count_preference%2Coffers_paid_membership%2Cpaid_member_count%2Cpatron_count%2Cpay_per_name%2Cpledge_sum%2Cshow_earnings%2Cshow_patron_count&json-api-version=1.0&json-api-use-default-includes=false&include=%5B%5D")

    static func membersURI(campaignID: String, cursor: String?) -> URI {
        var string = "https://www.patreon.com/api/oauth2/v2/campaigns/\(campaignID)/members"
            + "?fields%5Bmember%5D=patron_status,currently_entitled_amount_cents&page%5Bcount%5D=1000"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            string += "&page%5Bcursor%5D=\(encoded)"
        }
        return URI(string: string)
    }

    static func fundingCents(for req: Request) async throws -> Int {
        let memberSource = PatreonMemberFundingSource()
        let publicSource = PatreonPublicCampaignFundingSource()
        async let memberResult = fundingResult(from: memberSource, for: req)
        async let publicResult = fundingResult(from: publicSource, for: req)
        let results = await [memberResult, publicResult]
        let amounts = results.compactMap(\.amount)
        guard let lowestAmount = amounts.min() else {
            throw Abort(.badGateway, reason: "Both Patreon funding sources failed")
        }
        return lowestAmount
    }

    private static func fundingResult(
        from source: PatreonFundingSource,
        for req: Request
    ) async -> (amount: Int?, source: String) {
        do {
            let amount = try await source.fundingCents(for: req)
            req.logger.info("\(source.name) funding obtained: \(amount) cents")
            return (amount, source.name)
        } catch {
            req.logger.error("\(source.name) funding unavailable: \(error)")
            return (nil, source.name)
        }
    }

    static func patreonData(_ uri: URI, req: Request, headers: HTTPHeaders = .init()) async throws -> Data {
        let patreon = try await req.client.get(uri, headers: headers)
        guard patreon.status == .ok, let body = patreon.body else {
            throw Abort(.badGateway, reason: "Patreon API returned HTTP \(patreon.status.code)")
        }
        return Data(body.readableBytesView)
    }

    private func response(_ value: String, status: HTTPResponseStatus = .ok) -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return Response(status: status, headers: headers, body: .init(string: "{\"status\":\"\(value)\"}"))
    }

    static func render(_ svg: String, to directory: String) throws {
        let identifier = UUID().uuidString
        let base = URL(fileURLWithPath: directory)
        let input = base.appendingPathComponent(".progress-\(identifier).svg")
        let output = base.appendingPathComponent(".progress-\(identifier).png")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try svg.write(to: input, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsvg-convert")
        process.arguments = ["--output", output.path, input.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProgressError.renderingFailed }
        let destination = base.appendingPathComponent("progressDashboard.png")
        guard rename(output.path, destination.path) == 0 else { throw ProgressError.renderingFailed }
    }
}
