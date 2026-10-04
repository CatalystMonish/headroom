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

	// MARK: polling
	// Every minute. When the endpoint rate-limits us (429, e.g. other apps poll
	// it too), check every 2 minutes for the next 15, then go back to every
	// minute on our own. Another 429 restarts the 15 minutes.
	static let fastInterval: TimeInterval = 60
	static let slowInterval: TimeInterval = 120
	static let slowFor: TimeInterval = 15 * 60
	@Published private(set) var slowUntil: Date?
	private var nextFetch = Date.distantPast // no automatic fetch before this

	var isSlowedDown: Bool { (slowUntil ?? .distantPast) > Date() }
	// manual refreshes are instant, except while slowed down
	var canRefreshNow: Bool { !isSlowedDown || Date() >= nextFetch }

	func start() {
		refresh()
		timer?.invalidate()
		// tick often; refresh() decides whether a fetch is due
		timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.refresh(manual: false) }
		}
	}

	func refresh(manual: Bool = true) {
		guard !loading else { return }
		if (!manual || isSlowedDown), Date() < nextFetch { return }
		loading = true
		Task {
			let r = await ClaudeUsage.fetch()
			loading = false
			let now = Date()
			var wait: TimeInterval = 0
			switch r {
			case .success(let snap):
				snapshot = snap
				error = nil
				lastUpdated = now
				log("ok")
			case .failure(let e):
				if case .rateLimited(let after) = e {
					slowUntil = now.addingTimeInterval(Self.slowFor)
					wait = after ?? 0 // the server's Retry-After, if longer than our interval
				}
				error = e // keep showing the last good data on transient errors
				log(e.label)
			}
			let interval = (slowUntil ?? .distantPast) > now ? Self.slowInterval : Self.fastInterval
			nextFetch = now.addingTimeInterval(max(interval, wait))
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
