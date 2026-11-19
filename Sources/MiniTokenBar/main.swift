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
            balance = number.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(0...2)))
        } else { balance = nil }
        let resets = (json["rate_limit_reset_credits"] as? [String: Any])?["available_count"] as? Int
        return QuotaSnapshot(plan: plan, groups: groups, balance: balance, resets: resets)
    }
}
final class QuotaModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var loading = false
    @Published var error: String?
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
func quotaPanelFrame(anchor: NSRect, visibleFrame: NSRect, contentHeight: CGFloat = 590) -> NSRect {
    let safe = visibleFrame.insetBy(dx: 10, dy: 10)
    let size = NSSize(width: min(366, safe.width), height: min(contentHeight, safe.height))
    return NSRect(x: min(max(anchor.maxX - size.width, safe.minX), safe.maxX - size.width),
                  y: min(max(anchor.minY - size.height - 8, safe.minY), safe.maxY - size.height),
                  width: size.width, height: size.height)
}

func shouldDismissQuotaPanel(at point: NSPoint, panelFrame: NSRect, statusFrame: NSRect?) -> Bool {
    !panelFrame.contains(point) && statusFrame?.contains(point) != true
}

private func loadMark(_ name: String) -> NSImage? {
    let installed = Bundle.main.url(forResource: "MiniTokenBar_MiniTokenBar", withExtension: "bundle").flatMap { Bundle(url: $0) }
    let resources = installed ?? Bundle.module
    guard let url = resources.url(forResource: name, withExtension: "png", subdirectory: "Resources") else { return nil }
    return NSImage(contentsOf: url)
}

// Icon assets are exported from the Figma design itself: 24pt tiles, 8pt corners.
// Devin's asset has no tile of its own, so it sits inset on a white tile.
struct AppMark: View {
    let image: NSImage?
    let label: String
    var inset: CGFloat = 0
    var body: some View {
        ZStack {
            if inset > 0 { Color.white }
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 24 - inset * 2, height: 24 - inset * 2)
                    .clipShape(RoundedRectangle(cornerRadius: inset > 0 ? 4.5 : 8, style: .continuous))
            }
        }.frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(label)
    }
}

struct CodexMark: View {
    private static let mark = loadMark("codex-mark")
    var body: some View { AppMark(image: Self.mark, label: "Codex") }
}

struct ClaudeMark: View {
    private static let mark = loadMark("claude-mark")
    var body: some View { AppMark(image: Self.mark, label: "Claude") }
}

struct DevinMark: View {
    private static let mark = loadMark("devin-mark")
    var body: some View { AppMark(image: Self.mark, label: "Devin", inset: 2.37) }
}

// 1:1 with Figma node 9772:3749. Colors are sampled from the rendered export
// (opaque #1A1A1A card, so solid grays rather than translucent whites).
// Rows stack edge-to-edge; each row's own padding is the spacing:
// header 38, label 29, number 32, bar 24, caption 29, separator 25.
private enum Palette {
    static let title = Color(white: 179 / 255)
    static let trailing = Color(white: 164 / 255)
    static let label = Color(white: 179 / 255)
    static let number = Color.white
    static let dim = Color(white: 90 / 255)
    static let track = Color(red: 60 / 255, green: 60 / 255, blue: 63 / 255)
    static let separator = Color(white: 52 / 255)
    static let pink = Color(red: 1, green: 55 / 255, blue: 95 / 255)
}

// The design's card is Apple's "Liquid Glass - Regular" with a dark #1A1A1A tint
// (its fill layers are 70%/90% #1A1A1A). NSGlassEffectView only exists on
// macOS 26, and naming it directly would break the build on older SDKs/Command
// Line Tools — so it's looked up at runtime and configured via KVC, with a dark
// blur fallback everywhere else.
struct GlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat
    func makeNSView(context: Context) -> NSView {
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            glass.setValue(0, forKey: "style") // .regular
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            glass.setValue(NSColor(white: 26 / 255, alpha: 0.8), forKey: "tintColor")
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        return blur
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    @ObservedObject var claudeModel: ClaudeQuotaModel
    @ObservedObject var devinModel: DevinQuotaModel

    private static let personalCodexPlans: Set<String> = ["Pro 5x", "Pro", "Plus", "Free"]
    private var codexTrailing: String? {
        guard let plan = model.snapshot?.plan, plan != "API" else { return model.snapshot?.plan }
        return (Self.personalCodexPlans.contains(plan) ? "Personal " : "Corporate ") + plan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(CodexMark(), "Codex", url: "https://chatgpt.com/codex/settings/usage", trailing: codexTrailing)
            if let snapshot = model.snapshot, let general = snapshot.groups.first, !general.windows.isEmpty {
                windowsRow(general.windows, caption: resetText)
                if snapshot.balance != nil || snapshot.resets != nil {
                    caption(Text("Credits: \(snapshot.balance ?? "—"), Resets: \(snapshot.resets.map(String.init) ?? "—")"))
                }
            } else if let snapshot = model.snapshot {
                caption(Text(snapshot.plan == "API" ? "Subscription usage is not available in API mode." : "No usage window reported."))
            } else if model.error == nil {
                caption(Text("Loading…"))
            }
            if let error = model.error { caption(Text(error).foregroundStyle(Palette.pink)) }

            separator()
            header(ClaudeMark(), "Claude", url: "https://claude.ai/settings/usage", trailing: AccountLabels.claude)
            if let snapshot = claudeModel.snapshot, let general = snapshot.groups.first, !general.windows.isEmpty {
                // Claude Desktop's cache has no reset times; show how fresh the numbers are instead.
                windowsRow(general.windows) { _ in "As of " + Self.resetFormatter.string(from: snapshot.sampledAt) }
            } else if claudeModel.error == nil {
                caption(Text("Loading…"))
            }
            if let error = claudeModel.error { caption(Text(error).foregroundStyle(Palette.pink)) }

            separator()
            header(DevinMark(), "Devin", url: "https://app.devin.ai/settings/usage-limits", trailing: devinModel.snapshot?.accountTrailing)
            if let snapshot = devinModel.snapshot, let general = snapshot.groups.first, !general.windows.isEmpty {
                windowsRow(general.windows, caption: resetText)
                if let extraUsage = snapshot.extraUsageText {
                    caption(Text("Extra usage: ") + Text(extraUsage).foregroundStyle(Palette.pink))
                }
            } else if devinModel.error == nil {
                caption(Text("Loading…"))
            }
            if let error = devinModel.error { caption(Text(error).foregroundStyle(Palette.pink)) }
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .frame(width: 366, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GlassBackground(cornerRadius: 34))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func header(_ mark: some View, _ title: String, url: String, trailing: String?) -> some View {
        HStack(spacing: 6) {
            Button(action: { NSWorkspace.shared.open(URL(string: url)!) }) {
                HStack(spacing: 8) {
                    mark
                    Text(title).font(.system(size: 15, weight: .medium)).tracking(-0.43)
                        .foregroundStyle(Palette.title)
                        .frame(height: 18).padding(.vertical, 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open usage & limits")
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .regular)).tracking(-0.08)
                    .foregroundStyle(Palette.trailing).lineLimit(1).frame(height: 15)
            }
        }.frame(height: 38)
    }
    private func windowsRow(_ windows: [QuotaWindow], caption: @escaping (QuotaWindow) -> String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.seconds == 18000 ? "5h" : window.label)
                        .font(.system(size: 13, weight: .regular)).tracking(-0.08)
                        .foregroundStyle(Palette.label)
                        .frame(height: 15).padding(.top, 10).padding(.bottom, 4)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(window.remaining)").font(.system(size: 32, weight: .medium)).tracking(-0.43)
                            .foregroundStyle(Palette.number)
                        Text("%").font(.system(size: 24, weight: .regular)).foregroundStyle(Palette.dim)
                    }.monospacedDigit().frame(height: 32, alignment: .bottom)
                    bar(window).frame(height: 24)
                    self.caption(Text(caption(window)))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func bar(_ window: QuotaWindow) -> some View {
        let fraction = CGFloat(max(0, min(100, window.remaining))) / 100
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(Color.white).frame(width: max(6, geometry.size.width * fraction))
            }
        }.frame(height: 6).accessibilityLabel("\(window.remaining) percent remaining")
    }
    private func caption(_ text: Text) -> some View {
        text.font(.system(size: 13, weight: .regular)).tracking(-0.08)
            .foregroundStyle(Palette.dim).lineLimit(1)
            .frame(height: 15).padding(.top, 4).padding(.bottom, 10)
    }
    private func separator() -> some View {
        Rectangle().fill(Palette.separator).frame(height: 1).padding(.vertical, 12)
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
    private var host: QuotaHostingView!
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MiniTokenBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex …  |  Claude …  |  Devin …"
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A nonactivating panel must not implicitly hide on app deactivation:
        // AppKit can leave isVisible true even while the panel is hidden.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        host = QuotaHostingView(rootView: QuotaPanel(model: model, claudeModel: claudeModel, devinModel: devinModel))
        // Needed for fittingSize: with no sizing options NSHostingView reports 0x0,
        // which made the content-hugging panel zero-height (invisible).
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfOutside()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.panel.orderOut(nil); return nil }
            if event.type == .keyDown, event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "q": NSApp.terminate(nil); return nil
                case "r": self.refresh(); return nil
                default: break
                }
            }
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
        // The panel hugs its content (the design has no empty footer space).
        let height = host.fittingSize.height
        panel.setFrame(quotaPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame, contentHeight: height), display: true)
    }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.orderOut(nil)
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if panel.isVisible { panel.orderOut(nil) }
        else { showPanel() }
    }
    @objc private func refreshFromMenu() { refresh() }
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
        // Content height changes as data/errors arrive; re-measure once SwiftUI has re-rendered.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.positionPanel()
        }
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
