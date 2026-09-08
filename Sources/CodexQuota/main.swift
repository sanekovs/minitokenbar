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
        if windows.count == 1 { return "\(windows[0].remaining)%" }
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

// Keep the entire panel on the screen containing the status item, including
// secondary displays with negative origins and displays above the main screen.
func quotaPanelFrame(anchor: NSRect, visibleFrame: NSRect) -> NSRect {
    let safe = visibleFrame.insetBy(dx: 10, dy: 10)
    let size = NSSize(width: min(340, safe.width), height: min(454, safe.height))
    return NSRect(x: min(max(anchor.maxX - size.width, safe.minX), safe.maxX - size.width),
                  y: min(max(anchor.minY - size.height - 8, safe.minY), safe.maxY - size.height),
                  width: size.width, height: size.height)
}

func shouldDismissQuotaPanel(at point: NSPoint, panelFrame: NSRect, statusFrame: NSRect?) -> Bool {
    !panelFrame.contains(point) && statusFrame?.contains(point) != true
}

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    let refresh: () -> Void
    let quit: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 18, weight: .medium))
                Text("Codex").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(model.snapshot?.plan ?? "Account")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.primary.opacity(0.07), in: Capsule())
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = model.snapshot {
                        if let general = snapshot.groups.first, !general.windows.isEmpty {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(Array(general.windows.enumerated()), id: \.offset) { _, window in
                                    primaryMetric(window, single: general.windows.count == 1)
                                }
                            }.padding(.horizontal, 22)
                        } else {
                            Text(snapshot.plan == "API" ? "Subscription usage is not available in API mode." : "No usage window reported.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 22)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(snapshot.groups.dropFirst().enumerated()), id: \.offset) { _, group in
                                HStack {
                                    Text(group.name.replacingOccurrences(of: "GPT-5.3-Codex-Spark", with: "Spark"))
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                                }.padding(.bottom, 4)
                                ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                                    additionalRow(window)
                                }
                                Divider().overlay(.primary.opacity(0.03)).padding(.vertical, 14)
                            }
                            HStack(alignment: .top, spacing: 20) {
                                smallMetric("Credits", value: snapshot.balance ?? "Unavailable")
                                smallMetric("Usage resets", value: snapshot.resets.map { "\($0) available" } ?? "Unavailable")
                            }
                        }.padding(18)
                            .background(.primary.opacity(scheme == .dark ? 0.035 : 0.025), in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 10)
                    } else {
                        HStack { ProgressView().controlSize(.small); Text("Loading usage…") }
                            .font(.system(size: 12)).padding(22)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .padding(.horizontal, 22).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            HStack(spacing: 7) {
                Button(action: refresh) { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 25, height: 28) }
                    .disabled(model.loading).keyboardShortcut("r").help("Refresh usage")
                Text(model.loading ? "Syncing…" : model.updated.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not synced")
                    .font(.system(size: 10))
                Spacer()
                Button(action: { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!) }) {
                    Image(systemName: "arrow.up.right").frame(width: 28, height: 28)
                }.help("Open usage & billing")
                Button(action: quit) { Image(systemName: "power").frame(width: 28, height: 28) }
                    .keyboardShortcut("q").help("Quit CodexQuota")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 10)
        }
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else {
                FrostedBackground()
                    .overlay(scheme == .dark ? Color.black.opacity(0.48) : Color.white.opacity(0.35))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }
    private func primaryMetric(_ window: QuotaWindow, single: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(window.label) remaining").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(window.remaining)").font(.system(size: single ? 50 : 38, weight: .semibold)).tracking(-2)
                Text("%").font(.system(size: single ? 28 : 20, weight: .medium)).foregroundStyle(.secondary)
            }.monospacedDigit()
            meter(window, color: .primary, height: 5)
            Text(resetText(window)).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func additionalRow(_ window: QuotaWindow) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(window.label).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(resetText(window)).font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 110, alignment: .leading)
            meter(window, color: scheme == .dark ? Color(red: 0.73, green: 0.65, blue: 0.98) : Color(red: 0.43, green: 0.31, blue: 0.72), height: 18)
            Text("\(window.remaining)%").font(.system(size: 20, weight: .semibold)).monospacedDigit()
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: 62, alignment: .trailing)
        }.padding(.vertical, 9)
    }
    private func meter(_ window: QuotaWindow, color: Color, height: CGFloat) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<20) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < Int(ceil(Double(window.remaining) / 5)) ? (window.remaining <= 10 ? Color.orange : color) : .primary.opacity(0.1))
                }
            }.frame(width: geometry.size.width)
        }.frame(height: height).accessibilityLabel("\(window.remaining) percent remaining")
    }
    private func resetText(_ window: QuotaWindow) -> String {
        guard let date = window.reset else { return "Reset not reported" }
        return "Resets " + (Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
    }
    private func smallMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class QuotaHostingView: NSHostingView<QuotaPanel> {
    // Controls should respond to the first click while another app is active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class QuotaWindowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = QuotaWindowPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private let model = QuotaModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex …"
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A nonactivating panel must not implicitly hide on app deactivation:
        // AppKit can leave isVisible true even while the panel is hidden.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = QuotaHostingView(rootView: QuotaPanel(model: model, refresh: { [weak self] in self?.refresh() }, quit: { NSApp.terminate(nil) }))
        host.sizingOptions = []
        panel.contentView = host
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfOutside()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.panel.orderOut(nil); return nil }
            if event.type != .keyDown { self.dismissIfOutside() }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    private var statusButtonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    private func dismissIfOutside() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        // Status-item events can be routed through a system window, so compare
        // screen coordinates instead of relying on NSEvent.window identity.
        guard shouldDismissQuotaPanel(at: point, panelFrame: panel.frame, statusFrame: statusButtonFrame) else { return }
        panel.orderOut(nil)
    }
    @objc private func screenChanged() { if panel.isVisible { positionPanel() } }
    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) ?? window.screen else { return }
        panel.setFrame(quotaPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame), display: true)
    }
    @objc private func togglePopover() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
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
                    if self.panel.isVisible { self.positionPanel() }
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
