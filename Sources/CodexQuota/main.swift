import AppKit
import Foundation

struct QuotaWindow {
    let label: String
    let remaining: Int
    let reset: Date?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let sourceItem = NSMenuItem(title: "Loading quota…", action: nil, keyEquivalent: "")
    private let fiveHourItem = NSMenuItem(title: "5-hour limit: —", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "Weekly limit: —", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let activityItem = NSMenuItem(title: "Today: loading…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "— · —"
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        statusItem.button?.toolTip = "Codex quota"

        [sourceItem, fiveHourItem, weeklyItem, resetItem, activityItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())
        let refreshMenuItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)
        let quit = NSMenuItem(title: "Quit CodexQuota", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // NSStatusItem owns this menu and macOS handles clicks itself.
        statusItem.menu = menu
        refresh()
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refreshClicked), userInfo: nil, repeats: true)
    }

    @objc private func refreshClicked() { refresh() }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    private func refresh() {
        updateActivity()
        Task { [weak self] in
            let result = await Self.fetchQuota()
            await MainActor.run { self?.apply(result) }
        }
    }

    private func apply(_ result: Result<(String, [QuotaWindow]), Error>) {
        switch result {
        case .success(let (source, windows)):
            sourceItem.title = source
            let five = windows.first(where: { $0.label == "5-hour" })
            let weekly = windows.first(where: { $0.label == "Weekly" })
            fiveHourItem.title = "5-hour limit: \(five.map { "\($0.remaining)% left" } ?? "Unavailable")"
            weeklyItem.title = "Weekly limit: \(weekly.map { "\($0.remaining)% left" } ?? "Unavailable")"
            let resets = [five, weekly].compactMap { window -> String? in
                guard let window, let date = window.reset else { return nil }
                return "\(window.label) resets \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            resetItem.title = resets.joined(separator: "  ·  ")
            let fiveText = five.map { "\($0.remaining)%" } ?? "—"
            let weekText = weekly.map { "\($0.remaining)%" } ?? "—"
            statusItem.button?.title = "\(fiveText) · \(weekText)"
        case .failure(let error):
            sourceItem.title = "Quota unavailable"
            fiveHourItem.title = error.localizedDescription
            weeklyItem.title = "Open Codex and sign in again if needed"
            resetItem.title = ""
            statusItem.button?.title = "— · —"
        }
    }

    private func updateActivity() {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite").path
        let start = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        let sql = "SELECT COALESCE(NULLIF(title,''),'Untitled'), COALESCE(model,'Unknown'), tokens_used FROM threads WHERE updated_at_ms >= \(start) ORDER BY tokens_used DESC LIMIT 1;"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-separator", " | ", db, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run(); process.waitUntilExit()
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            activityItem.title = raw.isEmpty ? "Today: no activity yet" : "Today’s largest task: \(raw)"
        } catch { activityItem.title = "Today: activity unavailable" }
    }

    private static func fetchQuota() async -> Result<(String, [QuotaWindow]), Error> {
        do {
            let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
            let authData = try Data(contentsOf: authURL)
            let root = try JSONSerialization.jsonObject(with: authData) as! [String: Any]
            if let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty {
                return .success(("Source: API", []))
            }
            guard let tokens = root["tokens"] as? [String: Any],
                  let access = (tokens["access_token"] ?? tokens["accessToken"]) as? String else {
                throw NSError(domain: "CodexQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Codex subscription session found"])
            }
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let account = (tokens["account_id"] ?? tokens["accountId"]) as? String {
                request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "CodexQuota", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not refresh quota"])
            }
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let rate = json["rate_limit"] as? [String: Any]
            let windows = [parse(rate?["primary_window"], label: "5-hour"), parse(rate?["secondary_window"], label: "Weekly")].compactMap { $0 }
            let plan = (json["plan_type"] as? String)?.capitalized ?? "Subscription"
            return .success(("Source: \(plan) subscription", windows))
        } catch { return .failure(error) }
    }

    private static func parse(_ raw: Any?, label: String) -> QuotaWindow? {
        guard let value = raw as? [String: Any], let used = (value["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let reset = (value["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(label: label, remaining: max(0, Int((100 - used).rounded())), reset: reset)
    }
}

// NSApplication.delegate is weak; this global is intentionally a strong lifetime owner.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
