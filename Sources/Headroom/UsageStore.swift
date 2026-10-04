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
	// Stats labelled by name in the menubar. Every other stat shows its time
	// left ("3h 11m") instead; storing the opt-outs makes that the default.
	@Published var nameLabels: [String] {
		didSet { UserDefaults.standard.set(nameLabels, forKey: "nameLabels") }
	}

	private var timer: Timer?

	init() {
		pinned = UserDefaults.standard.stringArray(forKey: "pinnedStats") ?? [] // nothing pinned: the menubar shows the logo
		barStyle = BarStyle(rawValue: UserDefaults.standard.string(forKey: "barStyle") ?? "") ?? .meterText
		nameLabels = UserDefaults.standard.stringArray(forKey: "nameLabels") ?? []
	}

	var stats: [UsageStat] { snapshot?.stats ?? [] }
	// pinned stats as the menubar labels them: time left, or name
	var pinnedStats: [UsageStat] {
		stats.filter { pinned.contains($0.id) }.map { s in
			guard showsTimeLeft(s.id), s.resetsAt != nil else { return s }
			var s = s
			s.short = ClaudeUsage.formatReset(s.resetsAt)
			return s
		}
	}

	func showsTimeLeft(_ id: String) -> Bool { !nameLabels.contains(id) }
	func setShowsTimeLeft(_ id: String, _ on: Bool) {
		if on { nameLabels.removeAll { $0 == id } } else if !nameLabels.contains(id) { nameLabels.append(id) }
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
