import Foundation

// Claude Desktop keeps a small local cache of its own plan-usage percentages
// (used to feed its system-tray usage rows) at this path. There is no documented
// API for this, so field names below were recovered from strings inside
// Claude.app/Contents/Resources/app.asar. The cache only has the data Claude
// Desktop itself has recently fetched, so values can be stale if Claude hasn't
// been opened in a while, and reset times are not included in this cache.
enum ClaudeQuotaError: LocalizedError {
    case notFound
    case empty

    var errorDescription: String? {
        switch self {
        case .notFound: return "Open Claude Desktop and sign in to see usage."
        case .empty: return "No Claude usage reported yet. Use Claude once it's open."
        }
    }
}

struct ClaudeQuotaSnapshot {
    let groups: [QuotaGroup]
    let sampledAt: Date
    // The tightest remaining percentage across all windows; used for the compact menu-bar figure.
    var menuPercent: Int? { groups.flatMap { $0.windows }.map(\.remaining).min() }
    // Claude Desktop stops refreshing this cache when its menu-bar icon hasn't
    // been opened for 24h ("background poll paused" in its log), so old samples
    // must not pass for current numbers.
    var isStale: Bool { Date().timeIntervalSince(sampledAt) > 15 * 60 }
}

enum ClaudeQuota {
    // Keys inside plan-usage-history.json's "u" map, reverse engineered from the
    // "dtr" lookup table in Claude Desktop's renderer bundle.
    private static let windowSeconds: [String: Int] = [
        "fh": 18_000, "sd": 604_800, "so": 604_800, "sn": 604_800, "oa": 604_800, "cw": 604_800, "om": 604_800,
    ]
    private static let groupNames: [String: String] = [
        "so": "Opus · weekly", "sn": "Sonnet · weekly", "oa": "Connected apps · weekly",
        "cw": "Cowork · weekly", "om": "Promotional grant · weekly",
    ]

    private static var historyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    static func fetch() -> Result<ClaudeQuotaSnapshot, Error> {
        let data: Data
        do { data = try Data(contentsOf: historyURL) } catch { return .failure(ClaudeQuotaError.notFound) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]], let last = samples.last,
              let millis = (last["t"] as? NSNumber)?.doubleValue, let usage = last["u"] as? [String: Any]
        else { return .failure(ClaudeQuotaError.empty) }

        func window(_ key: String) -> QuotaWindow? {
            guard let seconds = windowSeconds[key],
                  let used = (usage[key] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
            return QuotaWindow(seconds: seconds, remaining: Int(max(0, min(100, (100 - used).rounded()))), reset: nil)
        }

        var primary: [QuotaWindow] = []
        if let fh = window("fh") { primary.append(fh) }
        if let sd = window("sd") { primary.append(sd) }
        guard !primary.isEmpty else { return .failure(ClaudeQuotaError.empty) }

        var groups = [QuotaGroup(name: "General usage", windows: primary.sorted { $0.seconds < $1.seconds })]
        for key in ["so", "sn", "oa", "cw", "om"] {
            if let w = window(key) { groups.append(QuotaGroup(name: groupNames[key] ?? "Additional usage", windows: [w])) }
        }
        return .success(ClaudeQuotaSnapshot(groups: groups, sampledAt: Date(timeIntervalSince1970: millis / 1000)))
    }
}
