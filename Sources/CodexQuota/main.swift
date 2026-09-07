import AppKit
import SwiftUI
import Foundation

struct QuotaWindow {
    let seconds: Int
    let remaining: Int
    let reset: Date?
    var label: String {
        switch seconds {
        case 18000: return "5 hours"
        case 604800: return "Weekly"
        case 86400: return "Daily"
        case 3600...: return "\(seconds / 3600) hours"
        case 1...: return "\(seconds / 60) minutes"
        default: return "Usage limit"
        }
    }
    var shortLabel: String {
        switch seconds {
        case 18000: return "5h"
        case 604800: return "week"
        case 86400: return "day"
        default: return label
        }
    }
}
struct QuotaGroup {
    let name: String
    let windows: [QuotaWindow]
}
struct QuotaSnapshot {
    let plan: String
    let groups: [QuotaGroup]
    let balance: String?
    let resets: Int?
    var menuTitle: String {
        guard let windows = groups.first?.windows, !windows.isEmpty else { return "Codex —" }
        return windows.map { "\($0.remaining)% · \($0.shortLabel)" }.joined(separator: "  ")
    }
    static func parse(_ json: [String: Any]) -> QuotaSnapshot {
        func windows(_ raw: Any?) -> [QuotaWindow] {
            guard let rate = raw as? [String: Any] else { return [] }
            return ["primary_window", "secondary_window"].compactMap { key in
                guard let value = rate[key] as? [String: Any],
                      let used = (value["used_percent"] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
                let seconds = (value["limit_window_seconds"] as? NSNumber)?.intValue ?? 0
                let reset = (value["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return QuotaWindow(seconds: seconds, remaining: Int(max(0, min(100, (100 - used).rounded()))), reset: reset)
            }.sorted { $0.seconds < $1.seconds }
        }
        let rawPlan = json["plan_type"] as? String ?? "Subscription"
        let plan = ["prolite": "Pro · 5×", "pro": "Pro", "plus": "Plus", "free": "Free"][rawPlan] ?? rawPlan.capitalized
        var groups = [QuotaGroup(name: "General usage", windows: windows(json["rate_limit"]))]
        for extra in json["additional_rate_limits"] as? [[String: Any]] ?? [] {
            groups.append(QuotaGroup(name: extra["limit_name"] as? String ?? "Additional usage", windows: windows(extra["rate_limit"])))
        }
        let credits = json["credits"] as? [String: Any]
        let balance: String?
        if credits?["unlimited"] as? Bool == true { balance = "Unlimited" }
        else if let raw = credits?["balance"] as? String, let number = Double(raw) {
            balance = number.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        } else { balance = nil }
        let resets = (json["rate_limit_reset_credits"] as? [String: Any])?["available_count"] as? Int
        return QuotaSnapshot(plan: plan, groups: groups, balance: balance, resets: resets)
    }
}
final class QuotaModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var loading = false
    @Published var error: String?
    @Published var updated: Date?
}

struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    let refresh: () -> Void
    let quit: () -> Void
    private let accent = Color(red: 0.58, green: 0.79, blue: 0.70)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex").font(.system(size: 19, weight: .semibold))
                    Text("Usage & billing").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.snapshot?.plan ?? "Account")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.primary.opacity(0.06), in: Capsule())
            }
            if let snapshot = model.snapshot {
                ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(group.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        if group.windows.isEmpty {
                            Text("No usage window reported").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                                    windowCard(window)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 0) {
                    metric("Credits balance", value: snapshot.balance ?? "Unavailable")
                    Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 28).padding(.horizontal, 16)
                    metric("Usage resets", value: snapshot.resets.map { $0 == 0 ? "None available" : "\($0) available" } ?? "Unavailable")
                }.padding(.vertical, 2)
            } else if model.loading {
                HStack { ProgressView().controlSize(.small); Text("Loading usage…").font(.system(size: 12)) }.padding(.vertical, 28)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(model.loading).help("Refresh usage (⌘R)").keyboardShortcut("r")
                Text(model.loading ? "Refreshing…" : model.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not updated")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
                }) {
                    Image(systemName: "arrow.up.right").frame(width: 24, height: 26)
                }.buttonStyle(.plain).help("Open usage & billing")
                Button(action: quit) {
                    Image(systemName: "power").frame(width: 24, height: 26)
                }.buttonStyle(.plain).help("Quit CodexQuota (⌘Q)").keyboardShortcut("q")
            }.foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func windowCard(_ window: QuotaWindow) -> some View {
        let tint = window.remaining <= 10 ? Color.red : window.remaining <= 25 ? Color.orange : accent
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(window.remaining)%").font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-1).monospacedDigit()
                Text("left").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(tint).frame(width: geometry.size.width * Double(window.remaining) / 100)
                }
            }.frame(height: 4).accessibilityLabel("\(window.remaining) percent remaining")
            VStack(alignment: .leading, spacing: 3) {
                Text("Resets").foregroundStyle(.tertiary)
                Text(window.reset.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? "Not reported")
                    .foregroundStyle(.secondary)
            }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = QuotaModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex …"
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: QuotaPanel(model: model, refresh: { [weak self] in self?.refresh() }, quit: { NSApp.terminate(nil) }))
        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            refresh()
        }
    }
    private func refresh() {
        guard !model.loading else { return }
        model.loading = true
        Task { @MainActor [weak self] in
            let result = await Self.fetchQuota()
            do {
                guard let self else { return }
                self.model.loading = false
                switch result {
                case .success(let snapshot):
                    self.model.snapshot = snapshot
                    self.model.error = nil
                    self.model.updated = Date()
                    self.statusItem.button?.title = snapshot.menuTitle
                    self.statusItem.button?.toolTip = "Codex · " + snapshot.groups.flatMap { group in group.windows.map { "\(group.name), \($0.label): \($0.remaining)% left" } }.joined(separator: "\n")
                case .failure(let error):
                    self.model.error = error.localizedDescription
                    self.statusItem.button?.title = self.model.snapshot.map { "\($0.menuTitle) !" } ?? "Codex !"
                    self.statusItem.button?.toolTip = "Could not refresh. Displayed usage may be outdated."
                }
            }
        }
    }
    private static func fetchQuota() async -> Result<QuotaSnapshot, Error> {
        do {
            let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
            let authData = try Data(contentsOf: authURL)
            guard let root = try JSONSerialization.jsonObject(with: authData) as? [String: Any] else { throw failure("Could not read Codex session") }
            if let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty {
                return .success(QuotaSnapshot(plan: "API", groups: [], balance: nil, resets: nil))
            }
            guard let tokens = root["tokens"] as? [String: Any], let access = (tokens["access_token"] ?? tokens["accessToken"]) as? String else {
                throw failure("Open Codex and sign in to see usage.")
            }
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.timeoutInterval = 20
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let account = (tokens["account_id"] ?? tokens["accountId"]) as? String { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200 else { throw failure(status == 401 ? "Session expired. Sign in again in Codex." : "Could not refresh usage. Try again shortly.") }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Could not read usage response.") }
            return .success(QuotaSnapshot.parse(json))
        } catch { return .failure(error) }
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "CodexQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
