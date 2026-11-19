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
                Circle().fill(fallback)
            }
        }.frame(width: 24, height: 24).clipShape(Circle())
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

struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    @ObservedObject var claudeModel: ClaudeQuotaModel
    @ObservedObject var devinModel: DevinQuotaModel
    let refresh: () -> Void
    let quit: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!) }) {
                    HStack(spacing: 8) {
                        CodexMark()
                        Text("ChatGPT").font(.system(size: 14, weight: .semibold))
                    }
                }.buttonStyle(.plain).help("Open usage & billing")
                Spacer()
                Text(model.snapshot?.plan ?? "Account")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.primary.opacity(0.07), in: Capsule())
            }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                    } else {
                        HStack { ProgressView().controlSize(.small); Text("Loading usage…") }
                            .font(.system(size: 12)).padding(22)
                    }
                    if let snapshot = model.snapshot {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Credits").foregroundStyle(.secondary)
                                Spacer()
                                Text(snapshot.balance ?? "Unavailable").monospacedDigit()
                            }
                            HStack {
                                Text("Usage resets").foregroundStyle(.secondary)
                                Spacer()
                                Text(snapshot.resets.map { "\($0) available" } ?? "Unavailable").monospacedDigit()
                            }
                        }.font(.system(size: 11)).padding(.horizontal, 22)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .padding(.horizontal, 22).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().padding(.horizontal, 22)
                    claudeSection
                    Divider().padding(.horizontal, 22)
                    devinSection
                }.padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            HStack(spacing: 7) {
                Button(action: refresh) { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 25, height: 28) }
                    .disabled(model.loading).keyboardShortcut("r").help("Refresh usage")
                Text(model.loading ? "Syncing…" : model.updated.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not synced")
                    .font(.system(size: 10))
                Spacer()
                Button(action: quit) { Image(systemName: "power").frame(width: 28, height: 28) }
                    .keyboardShortcut("q").help("Quit MiniTokenBar")
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
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }) {
                    HStack(spacing: 8) {
                        ClaudeMark()
                        Text("Claude").font(.system(size: 14, weight: .semibold))
                    }
                }.buttonStyle(.plain).help("Open usage & limits")
                Spacer()
                if let badge = AccountLabels.claude { accountBadge(badge) }
            }.padding(.horizontal, 22)
            if let snapshot = claudeModel.snapshot {
                if let general = snapshot.groups.first, !general.windows.isEmpty {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(general.windows.enumerated()), id: \.offset) { _, window in
                            primaryMetric(window, single: general.windows.count == 1)
                        }
                    }.padding(.horizontal, 22)
                    if snapshot.groups.count > 1 {
                        VStack(spacing: 8) {
                            ForEach(Array(snapshot.groups.dropFirst().enumerated()), id: \.offset) { _, group in
                                ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                                    HStack { Text(group.name).font(.system(size: 11)).foregroundStyle(.secondary); Spacer() }
                                    additionalRow(window)
                                }
                            }
                        }.padding(.horizontal, 10)
                    }
                } else {
                    Text("No usage window reported.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 22)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Loading Claude usage…") }
                    .font(.system(size: 12)).padding(.horizontal, 22)
            }
            if let error = claudeModel.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 22).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var devinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: { NSWorkspace.shared.open(URL(string: "https://app.devin.ai/settings/usage-limits")!) }) {
                    HStack(spacing: 8) {
                        DevinMark()
                        Text("Devin").font(.system(size: 14, weight: .semibold))
                    }
                }.buttonStyle(.plain).help("Open usage & limits")
                Spacer()
                if let badge = devinModel.snapshot?.accountBadge { accountBadge(badge) }
            }.padding(.horizontal, 22)
            if let snapshot = devinModel.snapshot {
                if let general = snapshot.groups.first, !general.windows.isEmpty {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(general.windows.enumerated()), id: \.offset) { _, window in
                            primaryMetric(window, single: general.windows.count == 1)
                        }
                    }.padding(.horizontal, 22)
                } else {
                    Text("No usage window reported.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 22)
                }
                if let balance = snapshot.balance {
                    HStack {
                        Text("Extra usage balance").foregroundStyle(.secondary)
                        Spacer()
                        Text(balance).monospacedDigit().foregroundStyle(.red)
                    }.font(.system(size: 11)).padding(.horizontal, 22)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Loading Devin usage…") }
                    .font(.system(size: 12)).padding(.horizontal, 22)
            }
            if let error = devinModel.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 22).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func accountBadge(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.primary.opacity(0.07), in: Capsule())
            .lineLimit(1).fixedSize()
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
