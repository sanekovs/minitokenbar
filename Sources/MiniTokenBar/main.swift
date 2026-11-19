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
        let plan = ["prolite": "Pro 5x", "pro": "Pro", "plus": "Plus", "free": "Free"][rawPlan] ?? rawPlan.capitalized
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
final class ClaudeQuotaModel: ObservableObject {
    @Published var snapshot: ClaudeQuotaSnapshot?
    @Published var loading = false
    @Published var error: String?
}
final class DevinQuotaModel: ObservableObject {
    @Published var snapshot: DevinQuotaSnapshot?
    @Published var loading = false
    @Published var error: String?
}

// Keep the entire panel on the screen containing the status item, including
// secondary displays with negative origins and displays above the main screen.
func quotaPanelFrame(anchor: NSRect, visibleFrame: NSRect) -> NSRect {
    let safe = visibleFrame.insetBy(dx: 10, dy: 10)
    let size = NSSize(width: min(340, safe.width), height: min(640, safe.height))
    return NSRect(x: min(max(anchor.maxX - size.width, safe.minX), safe.maxX - size.width),
                  y: min(max(anchor.minY - size.height - 8, safe.minY), safe.maxY - size.height),
                  width: size.width, height: size.height)
}

func shouldDismissQuotaPanel(at point: NSPoint, panelFrame: NSRect, statusFrame: NSRect?) -> Bool {
    !panelFrame.contains(point) && statusFrame?.contains(point) != true
}

// Always dark, like a macOS Control Center item — regardless of the system
// appearance setting, since this mirrors that fixed-dark design exactly.
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private func loadMark(_ name: String) -> NSImage? {
    let installed = Bundle.main.url(forResource: "MiniTokenBar_MiniTokenBar", withExtension: "bundle").flatMap { Bundle(url: $0) }
    let resources = installed ?? Bundle.module
    guard let url = resources.url(forResource: name, withExtension: "png", subdirectory: "Resources") else { return nil }
    return NSImage(contentsOf: url)
}

// Source app icons keep a transparent margin around their squircle artwork, so a
// plain circular clip just reveals that margin's corners instead of a filled
// circle. Oversizing the image before clipping crops the margin away so the
// artwork bleeds edge-to-edge. The oversample factor is measured per icon from
// its actual opaque-content bounding box (24 / contentFraction) so each mark is
// cropped just enough — too much makes the artwork look pinched/cropped.
struct AppMark: View {
    let image: NSImage?
    let fallback: Color
    let label: String
    var innerSize: CGFloat = 24
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill().frame(width: innerSize, height: innerSize)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(fallback)
            }
        }.frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(label)
    }
}

struct CodexMark: View {
    private static let mark = loadMark("codex-mark")
    var body: some View { AppMark(image: Self.mark, fallback: Color.black.opacity(0.65), label: "Codex", innerSize: 24) }
}

struct ClaudeMark: View {
    private static let mark = loadMark("claude-mark")
    var body: some View { AppMark(image: Self.mark, fallback: Color(red: 0.82, green: 0.45, blue: 0.32), label: "Claude", innerSize: 28) }
}

struct DevinMark: View {
    private static let mark = loadMark("devin-mark")
    var body: some View { AppMark(image: Self.mark, fallback: Color.primary.opacity(0.2), label: "Devin", innerSize: 29) }
}

// Matches the Figma "Menu" design (macOS Control-Center style): always dark,
// plain continuous sliders with a knob, no capsule badges — just hierarchy
// through text color/weight. See node 9772:3749 in the Product/Sandbox file.
struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    @ObservedObject var claudeModel: ClaudeQuotaModel
    @ObservedObject var devinModel: DevinQuotaModel
    let refresh: () -> Void
    let quit: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let personalCodexPlans: Set<String> = ["Pro 5x", "Pro", "Plus", "Free"]
    private var codexTrailing: String? {
        guard let plan = model.snapshot?.plan, plan != "API" else { return model.snapshot?.plan }
        return (Self.personalCodexPlans.contains(plan) ? "Personal " : "Corp ") + plan
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    serviceHeader(mark: CodexMark(), title: "Codex", url: "https://chatgpt.com/codex/settings/usage", trailing: codexTrailing)
                    if let snapshot = model.snapshot {
                        if let general = snapshot.groups.first, !general.windows.isEmpty {
                            windowsRow(general.windows)
                            if snapshot.balance != nil || snapshot.resets != nil {
                                infoLine(Text("Credits: \(snapshot.balance ?? "—"), Resets: \(snapshot.resets.map(String.init) ?? "—")")
                                    .foregroundStyle(Color.white.opacity(0.4)))
                            }
                        } else {
                            Text(snapshot.plan == "API" ? "Subscription usage is not available in API mode." : "No usage window reported.")
                                .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4)).padding(.horizontal, 20).padding(.vertical, 10)
                        }
                    } else {
                        loadingRow("Loading Codex usage…")
                    }
                    if let error = model.error { errorRow(error) }
                    separator()
                    serviceHeader(mark: ClaudeMark(), title: "Claude", url: "https://claude.ai/settings/usage", trailing: AccountLabels.claude)
                    if let snapshot = claudeModel.snapshot {
                        if let general = snapshot.groups.first, !general.windows.isEmpty {
                            windowsRow(general.windows)
                        } else {
                            Text("No usage window reported.").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4)).padding(.horizontal, 20).padding(.vertical, 10)
                        }
                    } else {
                        loadingRow("Loading Claude usage…")
                    }
                    if let error = claudeModel.error { errorRow(error) }
                    separator()
                    serviceHeader(mark: DevinMark(), title: "Devin", url: "https://app.devin.ai/settings/usage-limits", trailing: devinModel.snapshot?.accountTrailing)
                    if let snapshot = devinModel.snapshot {
                        if let general = snapshot.groups.first, !general.windows.isEmpty {
                            windowsRow(general.windows)
                        } else {
                            Text("No usage window reported.").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4)).padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        if let extraUsage = snapshot.extraUsageText {
                            infoLine(Text("Extra usage: ").foregroundStyle(Color.white.opacity(0.4)) + Text(extraUsage).foregroundStyle(Self.pink))
                        }
                    } else {
                        loadingRow("Loading Devin usage…")
                    }
                    if let error = devinModel.error { errorRow(error) }
                }.padding(.vertical, 13)
            }.scrollIndicators(.hidden)
            HStack(spacing: 7) {
                Button(action: refresh) { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 25, height: 28) }
                    .disabled(model.loading).keyboardShortcut("r").help("Refresh usage")
                Text(model.loading ? "Syncing…" : model.updated.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not synced")
                    .font(.system(size: 10))
                Spacer()
                Button(action: quit) { Image(systemName: "power").frame(width: 28, height: 28) }
                    .keyboardShortcut("q").help("Quit MiniTokenBar")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 10)
        }
        .background {
            if reduceTransparency { Color(red: 0.08, green: 0.08, blue: 0.09) }
            else { FrostedBackground().overlay(Color.black.opacity(0.55)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
    }

    private func serviceHeader(mark: some View, title: String, url: String, trailing: String?) -> some View {
        HStack(spacing: 8) {
            Button(action: { NSWorkspace.shared.open(URL(string: url)!) }) {
                HStack(spacing: 8) {
                    mark
                    Text(title).font(.system(size: 15, weight: .semibold)).tracking(-0.43)
                        .foregroundStyle(Color.white.opacity(0.92))
                }
            }.buttonStyle(.plain).help("Open usage & limits")
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .medium)).tracking(-0.08)
                    .foregroundStyle(Color.white.opacity(0.45)).lineLimit(1)
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
    private func windowsRow(_ windows: [QuotaWindow]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in metricColumn(window) }
        }.padding(.horizontal, 20)
    }
    private func metricColumn(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(window.seconds == 18000 ? "5h" : window.label)
                .font(.system(size: 13, weight: .medium)).tracking(-0.08)
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 10).padding(.bottom, 4)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(window.remaining)").font(.system(size: 32, weight: .semibold)).tracking(-0.43)
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("%").font(.system(size: 24)).foregroundStyle(Color.white.opacity(0.25))
            }.monospacedDigit()
            Text(resetText(window)).font(.system(size: 13, weight: .medium)).tracking(-0.08)
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.top, 4).padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            slider(window).frame(height: 24)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private static let pink = Color(red: 1, green: 0.216, blue: 0.373)
    // No knob, no red/blue split — a plain white fill on a gray track.
    private func slider(_ window: QuotaWindow) -> some View {
        let fraction = CGFloat(max(0, min(100, window.remaining))) / 100
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.17)).frame(height: 6)
                Capsule().fill(Color.white).frame(width: max(6, geometry.size.width * fraction), height: 6)
            }
        }.frame(height: 6).accessibilityLabel("\(window.remaining) percent remaining")
    }
    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Color.white.opacity(0.45))
        }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 10)
    }
    private func errorRow(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 11)).foregroundStyle(.orange)
            .padding(.horizontal, 20).padding(.vertical, 6).fixedSize(horizontal: false, vertical: true)
    }
    private func infoLine(_ text: Text) -> some View {
        text.font(.system(size: 13, weight: .medium)).tracking(-0.08)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)
    }
    private func separator() -> some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            .padding(.horizontal, 20).padding(.vertical, 12)
    }
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM 'at' H:mm"
        return formatter
    }()
    private func resetText(_ window: QuotaWindow) -> String {
        guard let date = window.reset else { return "Reset not reported" }
        return "Resets " + Self.resetFormatter.string(from: date)
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
    private let claudeModel = ClaudeQuotaModel()
    private let devinModel = DevinQuotaModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex …  |  Claude …  |  Devin …"
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
        let host = QuotaHostingView(rootView: QuotaPanel(model: model, claudeModel: claudeModel, devinModel: devinModel, refresh: { [weak self] in self?.refresh() }, quit: { NSApp.terminate(nil) }))
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
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }
    private func showPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        refresh()
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
        // A hidden menu bar or a crowded notch can leave the status item without
        // an on-screen window. Opening from Finder must still show the panel.
        let anchorFrame = statusButtonFrame
        guard let screen = anchorFrame.flatMap({ anchor in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
        }) ?? NSScreen.main else { return }
        let anchor = anchorFrame ?? NSRect(x: screen.visibleFrame.maxX - 30, y: screen.visibleFrame.maxY, width: 20, height: 20)
        panel.setFrame(quotaPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame), display: true)
    }
    @objc private func togglePopover() {
        if panel.isVisible { panel.orderOut(nil) }
        else { showPanel() }
    }
    private func refresh() {
        refreshClaude()
        refreshDevin()
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
                    if self.panel.isVisible { self.positionPanel() }
                case .failure(let error):
                    self.model.error = error.localizedDescription
                }
                self.updateStatusTitle()
            }
        }
    }
    private func refreshClaude() {
        guard !claudeModel.loading else { return }
        claudeModel.loading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch ClaudeQuota.fetch() {
            case .success(let snapshot):
                self.claudeModel.snapshot = snapshot
                self.claudeModel.error = nil
            case .failure(let error):
                self.claudeModel.error = error.localizedDescription
            }
            self.claudeModel.loading = false
            self.updateStatusTitle()
        }
    }
    private func refreshDevin() {
        guard !devinModel.loading else { return }
        devinModel.loading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch DevinQuota.fetch() {
            case .success(let snapshot):
                self.devinModel.snapshot = snapshot
                self.devinModel.error = nil
            case .failure(let error):
                self.devinModel.error = error.localizedDescription
            }
            self.devinModel.loading = false
            self.updateStatusTitle()
        }
    }
    // Combines all services into one compact title, e.g. "94%  |  100%  |  12%".
    // Each side shows its tightest remaining window; full detail lives in the panel.
    private func updateStatusTitle() {
        func text(prefix: String, percent: Int?, failed: Bool, placeholder: String) -> String {
            guard let percent else { return failed ? "\(prefix) !" : placeholder }
            return failed ? "\(percent)% !" : "\(percent)%"
        }
        let codexPercent = model.snapshot?.groups.first?.windows.map(\.remaining).min()
        let codexText = text(prefix: "Codex", percent: codexPercent, failed: model.error != nil, placeholder: "Codex …")
        let claudeText = text(prefix: "Claude", percent: claudeModel.snapshot?.menuPercent, failed: claudeModel.error != nil, placeholder: "Claude …")
        let devinText = text(prefix: "Devin", percent: devinModel.snapshot?.menuPercent, failed: devinModel.error != nil, placeholder: "Devin …")
        statusItem.button?.attributedTitle = Self.statusTitle(codex: codexText, claude: claudeText, devin: devinText)
        var tooltipParts: [String] = []
        if let snapshot = model.snapshot {
            tooltipParts.append("Codex · " + snapshot.groups.flatMap { group in group.windows.map { "\(group.name), \($0.label): \($0.remaining)% left" } }.joined(separator: "\n"))
        }
        if let error = model.error { tooltipParts.append("Codex: \(error)") }
        if let snapshot = claudeModel.snapshot {
            tooltipParts.append("Claude · " + snapshot.groups.flatMap { group in group.windows.map { "\(group.name), \($0.label): \($0.remaining)% left" } }.joined(separator: "\n"))
        }
        if let error = claudeModel.error { tooltipParts.append("Claude: \(error)") }
        if let snapshot = devinModel.snapshot {
            tooltipParts.append("Devin · " + snapshot.groups.flatMap { group in group.windows.map { "\(group.name), \($0.label): \($0.remaining)% left" } }.joined(separator: "\n"))
        }
        if let error = devinModel.error { tooltipParts.append("Devin: \(error)") }
        statusItem.button?.toolTip = tooltipParts.isEmpty ? nil : tooltipParts.joined(separator: "\n\n")
    }
    // Thin, translucent, vertically-centered dividers between each service's number.
    private static func statusTitle(codex: String, claude: String, devin: String) -> NSAttributedString {
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .ultraLight),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.28),
            .baselineOffset: 0.5,
        ]
        let result = NSMutableAttributedString(string: codex, attributes: numberAttrs)
        for segment in [claude, devin] {
            result.append(NSAttributedString(string: " ", attributes: numberAttrs))
            result.append(NSAttributedString(string: "│", attributes: separatorAttrs))
            result.append(NSAttributedString(string: " ", attributes: numberAttrs))
            result.append(NSAttributedString(string: segment, attributes: numberAttrs))
        }
        return result
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
    private static func failure(_ message: String) -> NSError { NSError(domain: "MiniTokenBar", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
