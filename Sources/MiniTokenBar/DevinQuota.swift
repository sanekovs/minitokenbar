import Foundation

// Devin's desktop app is a Windsurf/VS Code fork. It caches its own plan and
// quota info (used to drive its in-editor usage UI) as a JSON blob inside the
// app's VS Code-style global state database, keyed "windsurf.reactSettings.
// cachedPlanInfoData:user-<id>". Reusing that cache avoids needing Devin's
// session token: we just read the same local file Devin itself already wrote.
enum DevinQuotaError: LocalizedError {
    case notFound
    case empty

    var errorDescription: String? {
        switch self {
        case .notFound: return "Open Devin and sign in to see usage."
        case .empty: return "No Devin usage reported yet. Use Devin once it's open."
        }
    }
}

struct DevinQuotaSnapshot {
    let groups: [QuotaGroup]
    let planName: String?
    let balance: String?
    var menuPercent: Int? { groups.flatMap { $0.windows }.map(\.remaining).min() }
    // Teams-tier plans are paid by an organization; everything else is an individual plan.
    var accountTrailing: String? {
        guard let planName else { return nil }
        return planName.lowercased().contains("team") ? "Corporate" : "Personal"
    }
    // The design's fixed "$X / $Y" look; the denominator isn't in this cache,
    // so it only appears once the user sets it (see AccountLabels).
    var extraUsageText: String? {
        guard let balance else { return nil }
        guard let limit = AccountLabels.devinExtraUsageLimit else { return balance }
        return "\(balance) / \(limit.formatted(.currency(code: "USD").precision(.fractionLength(0))))"
    }
}

enum DevinQuota {
    private static var stateDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Devin/User/globalStorage/state.vscdb")
    }

    static func fetch() -> Result<DevinQuotaSnapshot, Error> {
        guard FileManager.default.fileExists(atPath: stateDBURL.path) else { return .failure(DevinQuotaError.notFound) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", stateDBURL.path,
            "SELECT value FROM ItemTable WHERE key LIKE 'windsurf.reactSettings.cachedPlanInfoData:%' ORDER BY rowid DESC LIMIT 1;"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return .failure(DevinQuotaError.notFound) }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        else { return .failure(DevinQuotaError.empty) }

        func window(percentKey: String, resetKey: String, seconds: Int) -> QuotaWindow? {
            guard let quota = json["quota"] as? [String: Any],
                  let percent = (quota[percentKey] as? NSNumber)?.doubleValue, percent.isFinite else { return nil }
            let reset = (quota[resetKey] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return QuotaWindow(seconds: seconds, remaining: Int(max(0, min(100, percent.rounded()))), reset: reset)
        }
        var windows: [QuotaWindow] = []
        if let daily = window(percentKey: "dailyRemainingPercent", resetKey: "dailyResetAtUnix", seconds: 86_400) { windows.append(daily) }
        if let weekly = window(percentKey: "weeklyRemainingPercent", resetKey: "weeklyResetAtUnix", seconds: 604_800) { windows.append(weekly) }
        guard !windows.isEmpty else { return .failure(DevinQuotaError.empty) }

        let groups = [QuotaGroup(name: "General usage", windows: windows.sorted { $0.seconds < $1.seconds })]
        let balance = ((json["quota"] as? [String: Any])?["overageBalanceMicros"] as? NSNumber).map {
            ($0.doubleValue / 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        }
        return .success(DevinQuotaSnapshot(groups: groups, planName: json["planName"] as? String, balance: balance))
    }
}
