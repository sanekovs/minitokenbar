import Foundation

struct DailyActivity: Identifiable {
    let date: String
    let value: Double
    var reported = true
    var id: String { date }
}
struct ProfileActivity {
    let tokens: Double?
    let streak: Int?
    let chats: Int?
    let peak: Double?
    let days: [DailyActivity]
    static func parse(_ json: [String: Any]) -> ProfileActivity? {
        guard let stats = json["stats"] as? [String: Any],
              ((json["metadata"] as? [String: Any])?["stats_error"] as? String ?? "").isEmpty else { return nil }
        return ProfileActivity(tokens: number(stats["lifetime_tokens"]), streak: (stats["current_streak_days"] as? NSNumber)?.intValue,
                               chats: (stats["total_threads"] as? NSNumber)?.intValue, peak: number(stats["peak_daily_tokens"]),
                               days: ((stats["daily_usage_buckets"] as? [[String: Any]]) ?? []).compactMap {
            guard let date = $0["start_date"] as? String, let value = number($0["tokens"]) else { return nil }
            return DailyActivity(date: date, value: value)
        }.sorted { $0.date < $1.date })
    }
}
struct ActivityAnalytics {
    let days: [DailyActivity]
    let credits: Double?
    let models: [(name: String, turns: Double)]
    var turns: Double { days.reduce(0) { $0 + $1.value } }
    static func parse(_ json: [String: Any]) -> ActivityAnalytics? {
        guard let rows = json["data"] as? [[String: Any]] else { return nil }
        var days: [DailyActivity] = [], models: [String: Double] = [:]
        var credits = 0.0, hasCredits = rows.isEmpty
        for row in rows {
            guard let date = row["date"] as? String, let totals = row["totals"] as? [String: Any], let turns = number(totals["turns"]) else { return nil }
            days.append(DailyActivity(date: date, value: turns))
            if let value = number(totals["credits"]) { credits += value; hasCredits = true }
            else { return nil }
            for model in row["models"] as? [[String: Any]] ?? [] {
                if let name = model["model"] as? String, let count = number(model["turns"]) { models[name, default: 0] += count }
            }
        }
        return ActivityAnalytics(days: days.sorted { $0.date < $1.date }, credits: hasCredits ? credits : nil,
                                 models: models.filter { $0.value > 0 }.map { (name: $0.key, turns: $0.value) }.sorted { $0.turns == $1.turns ? $0.name < $1.name : $0.turns > $1.turns })
    }
}
private func number(_ raw: Any?) -> Double? {
    guard let value = (raw as? NSNumber)?.doubleValue, value.isFinite, value >= 0 else { return nil }
    return value
}
func compactCount(_ value: Double?) -> String {
    guard let value else { return "—" }
    for (scale, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] {
        if value >= scale { return (value / scale).formatted(.number.precision(.fractionLength(0...1))) + suffix }
    }
    return value.formatted(.number.precision(.fractionLength(0)))
}
func utcDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
// Missing dates remain unknown, rather than implying zero activity.
func recentActivity(_ days: [DailyActivity], count: Int, now: Date = Date()) -> [DailyActivity] {
    var lookup: [String: DailyActivity] = [:]
    for day in days { lookup[day.date] = day }
    return (0..<count).map { offset in
        let date = utcDay(now.addingTimeInterval(-Double(count - 1 - offset) * 86400))
        return lookup[date] ?? DailyActivity(date: date, value: 0, reported: false)
    }
}
struct InsightsResult {
    var profile: ProfileActivity?
    var analytics: ActivityAnalytics?
}
enum InsightsService {
    static func fetch() async -> InsightsResult {
        do {
            let auth = try Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json"))
            guard let root = try JSONSerialization.jsonObject(with: auth) as? [String: Any],
                  let tokens = root["tokens"] as? [String: Any],
                  let access = (tokens["access_token"] ?? tokens["accessToken"]) as? String else { return InsightsResult() }
            let account = (tokens["account_id"] ?? tokens["accountId"]) as? String
            let now = Date(), start = utcDay(Date().addingTimeInterval(-6 * 86400))
            async let profile = get("profiles/me", access: access, account: account)
            async let analytics = get("analytics/daily-workspace-usage-counts?start_date=\(start)&end_date=\(utcDay(now))&group_by=day&workspace_user=true", access: access, account: account)
            let (p, a) = await (profile, analytics)
            return InsightsResult(profile: p.flatMap(ProfileActivity.parse), analytics: a.flatMap(ActivityAnalytics.parse))
        } catch { return InsightsResult() }
    }
    private static func get(_ path: String, access: String, account: String?) async -> [String: Any]? {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/" + path)!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }
}
