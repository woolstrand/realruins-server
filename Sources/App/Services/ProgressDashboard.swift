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

    var fraction: Double {
        guard let next = next else { return 1 }
        let start = previous?.amount ?? 0
        return min(1, max(0, (amount - start) / (next.amount - start)))
    }

    func svg() -> String {
        let width = 900
        let goalLines = targets.flatMap { target -> [(text: String, reached: Bool)] in
            let prefix = target.amount <= amount ? "✓" : "○"
            return wrapped("\(prefix)  \(target.title) — \(dollars(target.amount))", limit: 67)
                .map { (text: $0, reached: target.amount <= amount) }
        }
        let statusLines = wrapped(status?.description ?? "No current status", limit: 55)
        let height = 420 + statusLines.count * 31 + goalLines.count * 26
        var body = """
        <rect width="900" height="\(height)" fill="#101c2a"/>
        <rect x="24" y="24" width="852" height="\(height - 48)" rx="20" fill="#1b2d40"/>
        <text x="62" y="82" fill="#a9c4d9" font-size="22">MONTHLY PATREON SUPPORT</text>
        <text x="62" y="151" fill="#ffffff" font-size="54" font-weight="bold">\(dollars(amount)) / month</text>
        <rect x="62" y="186" width="776" height="32" rx="16" fill="#40546a"/>
        <rect x="62" y="186" width="\(Int(776 * fraction))" height="32" rx="16" fill="#55d6a0"/>
        """
        if let previous = previous {
            body += """
            <text x="62" y="255" fill="#55d6a0" font-size="18">✓ \(escape(shortLabel(previous.title))) · \(dollars(previous.amount)) reached</text>
            """
        }
        if let next = next {
            body += """
            <text x="838" y="255" text-anchor="end" fill="#f1d887" font-size="18">NEXT: \(escape(shortLabel(next.title))) · \(dollars(next.amount))</text>
            """
        } else {
            body += """
            <text x="838" y="255" text-anchor="end" fill="#55d6a0" font-size="18">ALL TARGETS REACHED</text>
            """
        }
        body += """
        <text x="62" y="302" fill="#a9c4d9" font-size="17">CURRENT STATUS</text>
        """
        for (index, line) in statusLines.enumerated() {
            body += """
            <text x="62" y="\(337 + index * 31)" fill="#ffffff" font-size="23">\(escape(line))</text>
            """
        }
        let goalsY = 363 + statusLines.count * 31
        body += """
        <text x="62" y="\(goalsY)" fill="#a9c4d9" font-size="17">TARGETS</text>
        """
        for (index, line) in goalLines.enumerated() {
            body += """
            <text x="62" y="\(goalsY + 33 + index * 26)" fill="\(line.reached ? "#55d6a0" : "#c6d4df")" font-size="17">\(escape(line.text))</text>
            """
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
        \(body)
        </svg>
        """
    }
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

private func shortLabel(_ value: String) -> String {
    value.count > 22 ? String(value.prefix(21)) + "…" : value
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

private struct PatreonCampaigns: Decodable {
    struct Campaign: Decodable {
        let id: String
        let attributes: Attributes
    }
    struct Attributes: Decodable {
        let pledge_sum: Double
    }
    let data: [Campaign]
}

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
            guard let token = Environment.get("PATREON_ACCESS_TOKEN"), !token.isEmpty else {
                throw Abort(.internalServerError, reason: "PATREON_ACCESS_TOKEN is not configured")
            }
            let config = try JSONDecoder().decode(
                ProgressConfig.self,
                from: Data(contentsOf: URL(fileURLWithPath: resourcesDirectory).appendingPathComponent("progress-targets.json"))
            )
            try config.validate()
            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: token)
            let campaignID = Environment.get("PATREON_CAMPAIGN_ID")
            let path = campaignID.map { "/\($0)" } ?? ""
            let patreon = try await req.client.get(
                URI(string: "https://www.patreon.com/api/oauth2/v2/campaigns\(path)?fields%5Bcampaign%5D=pledge_sum"),
                headers: headers
            )
            guard patreon.status == .ok, let body = patreon.body else {
                throw Abort(.badGateway, reason: "Patreon API returned HTTP \(patreon.status.code)")
            }
            let campaigns = try JSONDecoder().decode(PatreonCampaigns.self, from: Data(body.readableBytesView))
            let selected = campaignID == nil ? campaigns.data : campaigns.data.filter { $0.id == campaignID }
            guard selected.count == 1 else {
                throw Abort(.badGateway, reason: "Expected one Patreon campaign; configure PATREON_CAMPAIGN_ID if there are multiple")
            }
            let dashboard = try ProgressDashboard(amount: selected[0].attributes.pledge_sum / 100, config: config)
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
