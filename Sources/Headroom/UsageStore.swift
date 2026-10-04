import Foundation

// How pinned stats are drawn in the menubar.
enum BarStyle: String, CaseIterable, Identifiable {
	case text, coloredText, meter, meterText, dial
	var id: String { rawValue }
	var title: String {
		switch self {
		case .text: "Text"
		case .coloredText: "Color"
		case .meter: "Meter"
		case .meterText: "Meter+%"
		case .dial: "Dial"
		}
	}
}

// What labels each pinned stat in the menubar.
enum LabelMode: String, CaseIterable, Identifiable {
	case segment, timeLeft
	var id: String { rawValue }
	var title: String {
		switch self {
		case .segment: "Segment (5h · 7d)"
		case .timeLeft: "Time left (3h 11m)"
		}
	}
}

// Polls the Claude usage endpoint and holds the menubar prefs (which stats are
// pinned, and how they're drawn). Prefs live in UserDefaults, not config.json —
// they're companion-only, like suitePath.
@MainActor
final class UsageStore: ObservableObject {
	@Published private(set) var snapshot: UsageSnapshot?
	@Published private(set) var error: UsageError?
	@Published private(set) var lastUpdated: Date?
	@Published private(set) var loading = false

	@Published var pinned: [String] {
		didSet { UserDefaults.standard.set(pinned, forKey: "pinnedStats") }
	}
	@Published var barStyle: BarStyle {
		didSet { UserDefaults.standard.set(barStyle.rawValue, forKey: "barStyle") }
	}
	@Published var labelMode: LabelMode {
		didSet { UserDefaults.standard.set(labelMode.rawValue, forKey: "labelMode") }
	}

	private var timer: Timer?

	init() {
		pinned = UserDefaults.standard.stringArray(forKey: "pinnedStats") ?? [] // nothing pinned: the menubar shows the logo
		barStyle = BarStyle(rawValue: UserDefaults.standard.string(forKey: "barStyle") ?? "") ?? .meterText
		labelMode = LabelMode(rawValue: UserDefaults.standard.string(forKey: "labelMode") ?? "") ?? .segment
	}

	var stats: [UsageStat] { snapshot?.stats ?? [] }
	// pinned stats as the menubar labels them: the segment ("5h"), or the time left ("3h 11m")
	var pinnedStats: [UsageStat] {
		stats.filter { pinned.contains($0.id) }.map { s in
			guard labelMode == .timeLeft, s.resetsAt != nil else { return s }
			var s = s
			s.short = ClaudeUsage.formatReset(s.resetsAt)
			return s
		}
	}
	// last good data is still on screen, but the latest fetch failed
	var isStale: Bool { snapshot != nil && error != nil }

	func isPinned(_ id: String) -> Bool { pinned.contains(id) }
	func setPinned(_ id: String, _ on: Bool) {
		if on { if !pinned.contains(id) { pinned.append(id) } } else { pinned.removeAll { $0 == id } }
	}

	// real data every 60s, same cadence as the console tile
	func start() {
		refresh()
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.refresh() }
		}
	}

	func refresh() {
		guard !loading else { return }
		loading = true
		Task {
			let r = await ClaudeUsage.fetch()
			loading = false
			switch r {
			case .success(let snap):
				snapshot = snap
				error = nil
				lastUpdated = Date()
				log("ok")
			case .failure(let e):
				error = e // keep showing the last good data on transient errors
				log(e.label)
			}
		}
	}

	// visible when run from a terminal; handy when the endpoint changes
	private func log(_ s: String) { FileHandle.standardError.write(Data("headroom: usage \(s)\n".utf8)) }

	// called when the popup opens
	func refreshIfStale() {
		if let t = lastUpdated, Date().timeIntervalSince(t) < 30, error == nil { return }
		refresh()
	}
}
